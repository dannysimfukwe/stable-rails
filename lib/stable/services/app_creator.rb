# frozen_string_literal: true

module Stable
  module Services
    class AppCreator
      def initialize(name, options)
        @name = name
        @options = options
      end

      def call
        ruby = @options[:ruby] || RUBY_VERSION
        port = @options[:port] || next_free_port
        app_path = File.join(Stable::Paths.projects_dir, @name)
        domain = "#{@name}.test"

        # --- Check if app already exists ---
        config_file = Stable::Paths.app_config_file(@name)
        abort "App '#{@name}' already exists" if File.exist?(config_file)

        # --- Register app in registry ---
        Services::AppRegistry.add(
          name: @name, path: app_path, domain: domain, port: port,
          ruby: ruby, started_at: nil, pid: nil
        )

        # --- Ensure Ruby version & RVM ---
        Ruby.ensure_version(ruby)
        Ruby.ensure_rvm!

        # --- Create gemset ---
        System::Shell.run("bash -lc 'source #{Ruby.rvm_script} && rvm #{ruby} do rvm gemset create #{@name} || true'")

        rvm_cmd = Ruby.rvm_prefix(ruby, @name)

        # --- Install Bundler ---
        System::Shell.run("bash -lc '#{rvm_cmd} gem install bundler --no-document'")

        # --- Install Rails if missing ---
        rails_version = @options[:rails]
        rails_check_cmd = rails_version ? "#{rvm_cmd} gem list -i rails -v #{rails_version}" : "#{rvm_cmd} gem list -i rails"
        unless system("bash -lc '#{rails_check_cmd}'")
          puts "Installing Rails #{rails_version || 'latest'}..."
          install_cmd = rails_version ? "#{rvm_cmd} gem install rails -v #{rails_version}" : "#{rvm_cmd} gem install rails"
          system("bash -lc '#{install_cmd}'") or abort("Failed to install Rails #{rails_version || ''}")
        end

        # --- Create Rails app ---
        puts "Creating Rails app #{@name} (Ruby #{ruby})..."
        System::Shell.run("bash -lc '#{rvm_cmd} rails new #{app_path} \
                              --skip-importmap  \
                              --skip-hotwire  \
                              --skip-javascript  \
                              --skip-solid'")

        # --- Write ruby version/gemset ---
        Dir.chdir(app_path) do
          File.write('.ruby-version', "#{ruby}\n")
          File.write('.ruby-gemset', "#{@name}\n")
        end

        # --- Database integration ---
        if @options[:db]
          adapter = @options[:mysql] ? :mysql : :postgresql
          gem_name = adapter == :postgresql ? 'pg' : 'mysql2'
          gemfile_path = File.join(app_path, 'Gemfile')

          unless File.read(gemfile_path).include?(gem_name)
            File.open(gemfile_path, 'a') do |f|
              f.puts "\n# Added by Stable CLI"
              f.puts "gem '#{gem_name}'"
            end
            puts "✅ Added '#{gem_name}' gem to Gemfile"
          end

          # Use correct Ruby/gemset for bundle install
          System::Shell.run(rvm_run('bundle install --jobs=4 --retry=3', chdir: app_path))

          db_adapter = adapter == :mysql ? Database::MySQL : Database::Postgres
          db_adapter.new(app_name: @name, app_path: app_path, ruby: ruby).setup
        end

        # --- Run bundle & DB prepare ---
        System::Shell.run(rvm_run('bundle install --jobs=4 --retry=3', chdir: app_path))
        System::Shell.run(rvm_run('bundle exec rails db:prepare', chdir: app_path))

        rails_version = `bash -lc 'cd #{app_path} && #{rvm_cmd} bundle exec rails runner "puts Rails.version"'`.strip.to_f

        begin
          rails_ver = Gem::Version.new(rails_version)
        rescue ArgumentError
          rails_ver = Gem::Version.new('0.0.0')
        end

        # only if Rails >= 7
        if rails_ver >= Gem::Version.new('7.0.0')
          # Gems to re-add
          optional_gems = {
            'importmap-rails' => nil,
            'turbo-rails' => nil,
            'stimulus-rails' => nil,
            'solid_cache' => nil,
            'solid_queue' => nil,
            'solid_cable' => nil
          }

          gemfile = File.join(app_path, 'Gemfile')

          # Add gems if not already present
          optional_gems.each do |gem_name, version|
            next if File.read(gemfile).match?(/^gem ['"]#{gem_name}['"]/)

            File.open(gemfile, 'a') do |f|
              f.puts version ? "gem '#{gem_name}', '#{version}'" : "gem '#{gem_name}'"
            end
          end

          # Install all new gems
          System::Shell.run(rvm_run('bundle install', chdir: app_path))

          # Run generators for installed gems
          generators = [
            'importmap:install',
            'turbo:install stimulus:install',
            'solid_cache:install solid_queue:install solid_cable:install'
          ]

          generators.each do |cmd|
            System::Shell.run(rvm_run("bundle exec rails #{cmd}", chdir: app_path))
          end
        end

        # --- Add allowed host for Rails < 7.2 ---
        if @options[:rails] && @options[:rails].to_f < 7.2
          env_file = File.join(app_path, 'config/environments/development.rb')

          if File.exist?(env_file)
            content = File.read(env_file)

            # Append host config inside the Rails.application.configure block
            updated_content = content.gsub(/Rails\.application\.configure do(.*?)end/mm) do |_match|
              inner = Regexp.last_match(1)
              # Prevent duplicate entries
              unless inner.include?(domain)
                inner += "  # allow local .test host for this app\n  config.hosts << '#{domain}'\n"
              end
              "Rails.application.configure do#{inner}end"
            end

            File.write(env_file, updated_content)
          else
            warn "Development environment file not found: #{env_file}"
          end
        end

        # --- Hosts, certs, caddy ---
        Services::HostsManager.add(domain)
        Services::CaddyManager.add_app(@name, skip_ssl: @options[:skip_ssl])
        Services::CaddyManager.ensure_running!
        Services::CaddyManager.reload

        # --- Start Rails server ---
        puts "Starting Rails server for #{@name} on port #{port}..."
        log_file = File.join(app_path, 'log', 'stable.log')
        FileUtils.mkdir_p(File.dirname(log_file))

        abort "Port #{port} is already in use. Choose another port." if port_in_use?(port)

        pid = spawn(
          'bash', '-lc',
          "cd \"#{app_path}\" && #{rvm_cmd} bundle exec rails s -p #{port} -b 127.0.0.1",
          out: log_file, err: log_file
        )
        Process.detach(pid)
        AppRegistry.update(@name, started_at: Time.now.to_i, pid: pid)

        sleep 1.5
        wait_for_port(port)

        prefix = @options[:skip_ssl] ? 'http' : 'https'
        display_domain = @options[:skip_ssl] ? "#{domain}:#{port}" : domain
        puts "✔ #{@name} running at #{prefix}://#{display_domain}"
      end

      private

      def next_free_port
        used_ports = Services::AppRegistry.all.map { |a| a[:port] }
        port = 3000
        port += 1 while used_ports.include?(port) || port_in_use?(port)
        port
      end

      def port_in_use?(port)
        system("lsof -i tcp:#{port} > /dev/null 2>&1")
      end

      def wait_for_port(port, timeout: 20)
        require 'socket'
        start = Time.now

        loop do
          TCPSocket.new('127.0.0.1', port).close
          return
        rescue Errno::ECONNREFUSED
          raise "Rails never bound port #{port}. Check log/stable.log" if Time.now - start > timeout

          sleep 0.5
        end
      end

      def rvm_run(cmd, chdir: nil, ruby: nil)
        ruby ||= @options[:ruby] || RUBY_VERSION
        gemset = @name
        cd = chdir ? "cd #{chdir} && " : ''
        "bash -lc '#{cd}source #{Dir.home}/.rvm/scripts/rvm && rvm #{ruby}@#{gemset} do #{cmd}'"
      end
    end
  end
end
