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
        app_path = File.expand_path(@name)
        domain = "#{@name}.test"

        # --- Register app in registry ---
        Services::AppRegistry.add(name: @name, path: app_path, domain: domain, port: port, ruby: ruby, started_at: nil, pid: nil)

        abort "Folder already exists: #{app_path}" if File.exist?(app_path)

        # --- Ensure Ruby + gemset ---
        Ruby.ensure_version(ruby)
        Ruby.ensure_rvm!
        System::Shell.run("bash -lc 'source #{Ruby.rvm_script} && rvm #{ruby}@#{@name} --create do true'")

        rvm_cmd = Ruby.rvm_prefix(ruby, @name)

        # --- Install Rails into gemset if missing ---
        rails_version = @options[:rails]
        rails_check_cmd = if rails_version
                            "#{rvm_cmd} gem list -i rails -v #{rails_version}"
                          else
                            "#{rvm_cmd} gem list -i rails"
                          end

        unless system("bash -lc '#{rails_check_cmd}'")
          puts "Installing Rails #{rails_version || 'latest'} in gemset..."
          install_cmd = rails_version ? "#{rvm_cmd} gem install rails -v #{rails_version}" : "#{rvm_cmd} gem install rails"
          system("bash -lc '#{install_cmd}'") or abort('Failed to install Rails')
        end

        # --- Create Rails app ---
        puts "Creating Rails app #{@name} (Ruby #{ruby})..."
        System::Shell.run("bash -lc '#{rvm_cmd} rails new #{app_path}'")

        # --- Write ruby version/gemset and bundle install inside gemset ---
        Dir.chdir(app_path) do
          File.write('.ruby-version', "#{ruby}\n")
          File.write('.ruby-gemset', "#{@name}\n")

          puts 'Running bundle install...'
          System::Shell.run("bash -lc '#{rvm_cmd} bundle install --jobs=4 --retry=3'")
        end

        # --- Database integration ---
        if @options[:db]
          adapter = if @options[:mysql]
                      :mysql
                    else
                      :postgresql
                    end

          gem_name = adapter == :postgresql ? 'pg' : 'mysql2'
          gemfile_path = File.join(app_path, 'Gemfile')
          unless File.read(gemfile_path).include?(gem_name)
            File.open(gemfile_path, 'a') do |f|
              f.puts "\n# Added by Stable CLI"
              f.puts "gem '#{gem_name}'"
            end
            puts "✅ Added '#{gem_name}' gem to Gemfile"
          end

          # ensure gem is installed inside gemset
          System::Shell.run("bash -lc 'cd #{app_path} && #{rvm_cmd} bundle install --jobs=4 --retry=3'")

          # run adapter setup which will write database.yml and prepare
          db_adapter = adapter == :mysql ? Database::MySQL : Database::Postgres
          db_adapter.new(app_name: @name, app_path: app_path).setup
        end

        # --- Refresh bundle and prepare DB (idempotent) ---
        System::Shell.run("bash -lc 'cd #{app_path} && #{rvm_cmd} bundle check || #{rvm_cmd} bundle install'")
        System::Shell.run("bash -lc 'cd #{app_path} && #{rvm_cmd} bundle exec rails db:prepare'")

        # --- Hosts, certs, caddy ---
        Services::HostsManager.add(domain)
        Services::CaddyManager.add_app(@name, skip_ssl: @options[:skip_ssl])
        Services::CaddyManager.ensure_running!
        Services::CaddyManager.reload

        # --- Start the app ---
        puts "Starting Rails server for #{@name} on port #{port}..."
        log_file = File.join(app_path, 'log', 'stable.log')
        FileUtils.mkdir_p(File.dirname(log_file))

        abort "Port #{port} is already in use. Choose another port." if port_in_use?(port)

        pid = spawn('bash', '-lc', "cd \"#{app_path}\" && #{rvm_cmd} bundle exec rails s -p #{port} -b 127.0.0.1",
                    out: log_file, err: log_file)
        Process.detach(pid)

        AppRegistry.update(@name, started_at: Time.now.to_i, pid: pid)

        sleep 1.5
        wait_for_port(port)
        prefix = @options[:skip_ssl] ? 'http' : 'https'
        display_domain = if @options[:skip_ssl]
                          "#{domain}:#{port}"
                        else
                          domain
                        end

        puts "✔ #{@name} running at #{prefix}://#{display_domain}"
      end

      private

      def create_rails_app
        System::Shell.run("rails new #{@name}")
      end

      def setup_database
        return unless @options[:mysql] || @options[:postgres]

        adapter =
          if @options[:mysql]
            Database::MySQL
          else
            Database::Postgres
          end

        adapter.new(@name).setup
      end

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
    end
  end
end
