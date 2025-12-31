# frozen_string_literal: true

require 'thor'
require 'etc'
require 'fileutils'
require_relative 'scanner'
require_relative 'registry'

module Stable
  class CLI < Thor
    HOSTS_FILE = '/etc/hosts'

    def initialize(*)
      super
      Stable::Bootstrap.run!
      ensure_dependencies!
    end

    def self.exit_on_failure?
      true
    end

    desc 'new NAME', 'Create, secure, and run a new Rails app'
    method_option :ruby, type: :string, desc: 'Ruby version (defaults to current Ruby)'
    method_option :rails, type: :string, desc: 'Rails version to install (optional)'
    method_option :port, type: :numeric, desc: 'Port to run Rails app on'
    method_option :skip_ssl, type: :boolean, default: false, desc: 'Skip HTTPS setup'
    def new(name, ruby: RUBY_VERSION, rails: nil, port: nil)
      port ||= next_free_port
      app_path = File.expand_path(name)

      abort "Folder already exists: #{app_path}" if File.exist?(app_path)

      # --- Ensure RVM and Ruby ---
      ensure_rvm!
      puts "Using Ruby #{ruby} with RVM gemset #{name}..."
      system("bash -lc 'rvm #{ruby}@#{name} --create do true'") or abort('Failed to create RVM gemset')

      # --- Install Rails in gemset if needed ---
      rails_version = rails || 'latest'
      rails_check = system("bash -lc 'rvm #{ruby}@#{name} do gem list -i rails#{rails ? " -v #{rails}" : ''}'")
      unless rails_check
        puts "Installing Rails #{rails_version} in gemset..."
        system("bash -lc 'rvm #{ruby}@#{name} do gem install rails #{rails ? "-v #{rails}" : ''}'") or abort('Failed to install Rails')
      end

      # --- Create Rails app ---
      puts "Creating Rails app #{name} (Ruby #{ruby})..."
      system("bash -lc 'rvm #{ruby}@#{name} do rails new #{app_path}'") or abort('Rails app creation failed')

      # --- Add .ruby-version and .ruby-gemset ---
      Dir.chdir(app_path) do
        File.write('.ruby-version', "#{ruby}\n")
        File.write('.ruby-gemset', "#{name}\n")

        # --- Install gems inside gemset ---
        puts 'Running bundle install...'
        system("bash -lc 'rvm #{ruby}@#{name} do bundle install --jobs=4 --retry=3'") or abort('bundle install failed')
      end

      # --- Add app to registry ---
      domain = "#{name}.test"
      apps = Registry.apps
      apps << { name: name, path: app_path, domain: domain, port: port, ruby: ruby }
      Registry.save(apps)

      # --- Host entry & certificate ---
      add_host_entry(domain)
      generate_cert(domain) unless options[:skip_ssl]
      update_caddyfile(domain, port)
      ensure_caddy_running!
      caddy_reload

      # --- Start Rails server ---
      puts "Starting Rails server for #{name} on port #{port}..."
      log_file = File.join(app_path, 'log', 'stable.log')
      FileUtils.mkdir_p(File.dirname(log_file))
      pid = spawn("bash -lc 'rvm #{ruby}@#{name} do cd #{app_path} && bundle exec rails s -p #{port} >> #{log_file} 2>&1'")
      Process.detach(pid)

      wait_for_port(port)
      puts "✔ #{name} running at https://#{domain}"
    end

    desc 'list', 'List detected apps'
    def list
      apps = Registry.apps
      if apps.empty?
        puts 'No apps found.'
      else
        apps.each do |app|
          puts "#{app[:name]} -> https://#{app[:domain]}"
        end
      end
    end

    desc 'add FOLDER', 'Add a Rails app folder'
    def add(folder)
      folder = File.expand_path(folder)
      unless File.exist?(File.join(folder, 'config', 'application.rb'))
        puts "Not a Rails app: #{folder}"
        return
      end

      apps = Registry.apps
      name = File.basename(folder)
      domain = "#{name}.test"

      if apps.any? { |a| a[:path] == folder }
        puts "App already exists: #{name}"
        return
      end

      port = next_free_port
      ruby = detect_ruby_version(folder)

      apps << { name: name, path: folder, domain: domain, port: port, ruby: ruby }
      Registry.save(apps)
      puts "Added #{name} -> https://#{domain} (port #{port})"

      add_host_entry(domain)
      generate_cert(domain)
      update_caddyfile(domain, port)
      caddy_reload
    end

    desc 'remove NAME', 'Remove an app by name'
    def remove(name)
      apps = Registry.apps
      app = apps.find { |a| a[:name] == name }
      if app.nil?
        puts "No app found with name #{name}"
        return
      end

      new_apps = apps.reject { |a| a[:name] == name }
      Registry.save(new_apps)
      puts "Removed #{name}"

      remove_host_entry(app[:domain])
      remove_caddy_entry(app[:domain])
      caddy_reload
    end

    desc 'start NAME', 'Start a Rails app with its correct Ruby version'
    def start(name)
      app = Registry.apps.find { |a| a[:name] == name }
      unless app
        puts "No app found with name #{name}"
        return
      end

      port = app[:port] || next_free_port
      ruby = app[:ruby]

      puts "Starting #{name} on port #{port}#{ruby ? " (Ruby #{ruby})" : ''}..."

      log_file = File.join(app[:path], 'log', 'stable.log')
      FileUtils.mkdir_p(File.dirname(log_file))

      ruby_exec =
        if ruby
          if rvm_available?
            ensure_rvm_ruby!(ruby)
            "rvm #{ruby}@#{name} do"
          elsif rbenv_available?
            ensure_rbenv_ruby!(ruby)
            "RBENV_VERSION=#{ruby}"
          else
            puts 'No Ruby version manager found (rvm or rbenv)'
            return
          end
        end

      cmd = <<~CMD
        cd #{app[:path]} &&
        #{ruby_exec} bundle exec rails s -p #{port}
      CMD

      pid = spawn(
        'bash',
        '-lc',
        cmd,
        out: log_file,
        err: log_file
      )

      Process.detach(pid)

      generate_cert(app[:domain])
      update_caddyfile(app[:domain], port)
      wait_for_port(port)
      caddy_reload

      puts "#{name} started on https://#{app[:domain]}"
    end

    desc 'stop NAME', 'Stop a Rails app (default port 3000)'
    def stop(name)
      app = Registry.apps.find { |a| a[:name] == name }

      output = `lsof -i tcp:#{app[:port]} -t`.strip
      if output.empty?
        puts "No app running on port #{app[:port]}"
      else
        output.split("\n").each { |pid| Process.kill('TERM', pid.to_i) }
        puts "Stopped #{name}"
      end
    end

    desc 'setup', 'Sets up Caddy and local trusted certificates'
    def setup
      FileUtils.mkdir_p(Stable::Paths.root)
      File.write(Stable::Paths.caddyfile, '') unless File.exist?(Stable::Paths.caddyfile)
      ensure_caddy_running!
      puts "Caddy home initialized at #{Stable::Paths.root}"
    end

    desc 'caddy reload', 'Reloads Caddy after adding/removing apps'
    def caddy_reload
      if system('which caddy > /dev/null')
        system("caddy reload --config #{Stable::Paths.caddyfile}")
        puts 'Caddy reloaded'
      else
        puts 'Caddy not found. Install Caddy first.'
      end
    end

    desc 'secure DOMAIN', 'Generate trusted local HTTPS cert for a specific folder/domain'
    def secure(domain)
      app = Registry.apps.find { |a| a[:domain] == domain }
      unless app
        puts "No app found with domain #{domain}"
        return
      end
      secure_app(domain, app[:path], app[:port])
      caddy_reload
      puts "Secured https://#{domain}"
    end

    desc 'doctor', 'Check Stable system health'
    def doctor
      puts "Stable doctor\n\n"

      puts "Ruby version: #{RUBY_VERSION}"
      puts "RVM: #{rvm_available? ? 'yes' : 'no'}"
      puts "rbenv: #{rbenv_available? ? 'yes' : 'no'}"
      puts "Caddy: #{system('which caddy > /dev/null') ? 'yes' : 'no'}"
      puts "mkcert: #{system('which mkcert > /dev/null') ? 'yes' : 'no'}"

      Registry.apps.each do |app|
        status = port_in_use?(app[:port]) ? 'running' : 'stopped'
        puts "#{app[:name]} → Ruby #{app[:ruby] || 'default'} (#{status})"
      end
    end

    desc 'upgrade-ruby NAME VERSION', 'Upgrade Ruby for an app'
    def upgrade_ruby(name, version)
      app = Registry.apps.find { |a| a[:name] == name }
      unless app
        puts "No app named #{name}"
        return
      end

      if rvm_available?
        system("bash -lc 'rvm install #{version}'")
      elsif rbenv_available?
        system("rbenv install #{version}")
      else
        puts 'No Ruby version manager found'
        return
      end

      File.write(File.join(app[:path], '.ruby-version'), version)
      app[:ruby] = version
      Registry.save(Registry.apps)

      puts "#{name} now uses Ruby #{version}"
    end

    private

    def add_host_entry(domain)
      entry = "127.0.0.1\t#{domain}"
      hosts = File.read(HOSTS_FILE)
      unless hosts.include?(domain)
        puts "Adding #{domain} to #{HOSTS_FILE}..."
        File.open(HOSTS_FILE, 'a') { |f| f.puts entry }
        system('dscacheutil -flushcache; sudo killall -HUP mDNSResponder')
      end
    rescue Errno::EACCES
      ensure_hosts_entry(domain)
    end

    def remove_host_entry(domain)
      hosts = File.read(HOSTS_FILE)
      new_hosts = hosts.lines.reject { |line| line.include?(domain) }.join
      File.write(HOSTS_FILE, new_hosts)
      system('dscacheutil -flushcache; sudo killall -HUP mDNSResponder')
    rescue Errno::EACCES
      puts "Permission denied updating #{HOSTS_FILE}. Run 'sudo stable remove #{domain}' to remove hosts entry."
    end

    def ensure_hosts_entry(domain)
      entry = "127.0.0.1\t#{domain}"

      hosts = File.read(HOSTS_FILE)
      return if hosts.include?(domain)

      if Process.uid.zero?
        File.open(HOSTS_FILE, 'a') { |f| f.puts entry }
      else
        system(%(echo "#{entry}" | sudo tee -a #{HOSTS_FILE} > /dev/null))
      end

      system('dscacheutil -flushcache; sudo killall -HUP mDNSResponder')
    end

    def secure_app(domain, _folder, port)
      ensure_certs_dir!

      cert_path = File.join(Stable::Paths.certs_dir, "#{domain}.pem")
      key_path  = File.join(Stable::Paths.certs_dir, "#{domain}-key.pem")

      # Generate certificates if missing
      if system('which mkcert > /dev/null')
        unless File.exist?(cert_path) && File.exist?(key_path)
          system("mkcert -cert-file #{cert_path} -key-file #{key_path} #{domain}")
        end
      else
        puts 'mkcert not found. Please install mkcert.'
        return
      end

      # Auto-add Caddy block if not already in Caddyfile
      add_caddy_block(domain, cert_path, key_path, port)
      caddy_reload
    end

    def add_caddy_block(domain, cert, key, port)
      caddyfile = Stable::Paths.caddyfile
      FileUtils.touch(caddyfile) unless File.exist?(caddyfile)
      content = File.read(caddyfile)

      return if content.include?(domain) # don't duplicate

      block = <<~CADDY

        https://#{domain} {
            reverse_proxy 127.0.0.1:#{port}
            tls #{cert} #{key}
        }
      CADDY

      File.write(caddyfile, content + block)
      system("caddy fmt --overwrite #{caddyfile}")
    end

    # Remove Caddyfile entry for the domain
    def remove_caddy_entry(domain)
      return unless File.exist?(Stable::Paths.caddyfile)

      content = File.read(Stable::Paths.caddyfile)
      # Remove block starting with https://<domain> { ... }
      regex = %r{
        https://#{Regexp.escape(domain)}\s*\{
        .*?
        \}
      }mx

      new_content = content.gsub(regex, '')

      File.write(Stable::Paths.caddyfile, new_content)
    end

    def ensure_dependencies!
      unless system('which brew > /dev/null')
        puts 'Homebrew is required. Install it first: https://brew.sh'
        exit 1
      end

      unless system('which caddy > /dev/null')
        puts 'Installing Caddy...'
        system('brew install caddy')
      end

      return if system('which mkcert > /dev/null')

      puts 'Installing mkcert...'
      system('brew install mkcert nss')
      system('mkcert -install')
    end

    def ensure_caddy_running!
      api_port = 2019

      # Check if Caddy API is reachable
      require 'socket'
      begin
        TCPSocket.new('127.0.0.1', api_port).close
        puts 'Caddy already running.'
      rescue Errno::ECONNREFUSED
        puts 'Starting Caddy in background...'
        system("caddy run --config #{Stable::Paths.caddyfile} --adapter caddyfile --watch --resume &")
        sleep 3
      end
    end

    def next_free_port
      used_ports = Registry.apps.map { |a| a[:port] }
      port = 3000
      port += 1 while used_ports.include?(port) || port_in_use?(port)
      port
    end

    def port_in_use?(port)
      system("lsof -i tcp:#{port} > /dev/null 2>&1")
    end

    def generate_cert(domain)
      cert_path = File.join(Stable::Paths.certs_dir, "#{domain}.pem")
      key_path  = File.join(Stable::Paths.certs_dir, "#{domain}-key.pem")
      FileUtils.mkdir_p(Stable::Paths.certs_dir)

      return if File.exist?(cert_path) && File.exist?(key_path)

      if system('which mkcert > /dev/null')
        system("mkcert -cert-file #{cert_path} -key-file #{key_path} #{domain}")
      else
        puts 'mkcert not found. Please install mkcert.'
      end
    end

    def update_caddyfile(domain, port)
      caddyfile = Stable::Paths.caddyfile
      FileUtils.touch(caddyfile) unless File.exist?(caddyfile)
      content = File.read(caddyfile)

      # remove existing block for domain
      regex = %r{
        https://#{Regexp.escape(domain)}\s*\{
        .*?
        \}
      }mx

      content = content.gsub(regex, '')

      # add new block
      cert_path = File.join(Stable::Paths.certs_dir, "#{domain}.pem")
      key_path  = File.join(Stable::Paths.certs_dir, "#{domain}-key.pem")
      block = <<~CADDY

        https://#{domain} {
            reverse_proxy 127.0.0.1:#{port}
            tls #{cert_path} #{key_path}
        }
      CADDY

      File.write(caddyfile, content + block)
      system("caddy fmt --overwrite #{caddyfile}")
    end

    def ensure_certs_dir!
      certs_dir = Stable::Paths.certs_dir
      FileUtils.mkdir_p(certs_dir)

      begin
        FileUtils.chown_R(Etc.getlogin, nil, certs_dir)
      rescue StandardError => e
        puts "Could not change ownership: #{e.message}"
      end

      # Restrict permissions for security
      Dir.glob("#{certs_dir}/*.pem").each do |pem|
        FileUtils.chmod(0o600, pem)
      end
    end

    def wait_for_port(port, timeout: 5)
      require 'socket'
      start_time = Time.now
      loop do
        TCPSocket.new('127.0.0.1', port).close
        break
      rescue Errno::ECONNREFUSED
        raise "Timeout waiting for port #{port}" if Time.now - start_time > timeout

        sleep 0.1
      end
    end

    def ensure_rvm!
      return if system('which rvm > /dev/null')

      puts 'RVM not found. Installing RVM...'

      install_cmd = <<~CMD
        curl -sSL https://get.rvm.io | bash -s stable
      CMD

      abort 'RVM installation failed' unless system(install_cmd)

      # Load RVM into current process
      rvm_script = File.expand_path('~/.rvm/scripts/rvm')
      abort 'RVM installed but could not be loaded' unless File.exist?(rvm_script)

      ENV['PATH'] = "#{File.expand_path('~/.rvm/bin')}:#{ENV['PATH']}"

      system(%(bash -lc "source #{rvm_script} && rvm --version")) ||
        abort('RVM installed but not functional')
    end

    def ensure_ruby_installed!(version)
      return if system("rvm list strings | grep ruby-#{version} > /dev/null")

      puts "Installing Ruby #{version}..."
      system("rvm install #{version}") || abort("Failed to install Ruby #{version}")
    end

    def detect_ruby_version(path)
      rv = File.join(path, '.ruby-version')
      return File.read(rv).strip if File.exist?(rv)

      gemfile = File.join(path, 'Gemfile')
      if File.exist?(gemfile)
        ruby_line = File.read(gemfile)[/^ruby ['"](.+?)['"]/, 1]
        return ruby_line if ruby_line
      end

      nil
    end

    def rvm_available?
      system("bash -lc 'command -v rvm > /dev/null'")
    end

    def rbenv_available?
      system('command -v rbenv > /dev/null')
    end

    def ensure_rvm_ruby!(version)
      system("bash -lc 'rvm list strings | grep -q #{version} || rvm install #{version}'")
    end

    def ensure_rbenv_ruby!(version)
      system("rbenv versions | grep -q #{version} || rbenv install #{version}")
    end
  end
end
