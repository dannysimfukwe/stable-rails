# frozen_string_literal: true

require 'thor'
require 'etc'
require 'tempfile'
require 'fileutils'
require 'io/console'
require_relative 'scanner'
require_relative 'registry'

module Stable
  class CLI < Thor
    HOSTS_FILE = '/etc/hosts'

    def initialize(*)
      super
      Stable::Bootstrap.run!
      Services::SetupRunner.ensure_dependencies!
      dedupe_registry!
    end

    def self.exit_on_failure?
      true
    end

    desc 'new NAME', 'Create, secure, and run a new Rails app'
    method_option :ruby, type: :string, desc: 'Ruby version (defaults to current Ruby)'
    method_option :rails, type: :string, desc: 'Rails version to install (optional)'
    method_option :port, type: :numeric, desc: 'Port to run Rails app on'
    method_option :skip_ssl, type: :boolean, default: false, desc: 'Skip HTTPS setup'
    method_option :db, type: :string, desc: 'Database name to create and integrate'
    method_option :postgres, type: :boolean, default: false, desc: 'Use Postgres for the database'
    method_option :mysql, type: :boolean, default: false, desc: 'Use MySQL for the database'
    def new(name, ruby: RUBY_VERSION, rails: nil, port: nil)
      Commands::New.new(name, options).call
    end

    desc 'list', 'List detected apps'
    def list
      Commands::List.new.call
    end

    desc 'add FOLDER', 'Add a Rails app folder'
    def add(folder)
      folder = File.expand_path(folder)
      unless File.exist?(File.join(folder, 'config', 'application.rb'))
        puts "Not a Rails app: #{folder}"
        return
      end

      puts "Detected gemset: #{File.read('.ruby-gemset').strip}" if File.exist?('.ruby-gemset')

      name = File.basename(folder)
      domain = "#{name}.test"

      if Services::AppRegistry.all.any? { |a| a[:path] == folder }
        puts "App already exists: #{name}"
        return
      end

      port = next_free_port
      ruby = Stable::Services::Ruby.detect_ruby_version(folder)

      app = { name: name, path: folder, domain: domain, port: port, ruby: ruby }
      Services::AppRegistry.add_app(app)
      puts "Added #{name} -> https://#{domain} (port #{port})"

      Services::HostsManager.add(domain)
      Services::CaddyManager.add_app(name, skip_ssl: options[:skip_ssl])
      Services::CaddyManager.reload
    end

    desc 'remove NAME', 'Remove an app by name'
    def remove(name)
      Commands::Remove.new(name).call
    end

    desc 'start NAME', 'Start a Rails app with its correct Ruby version'
    def start(name)
      Commands::Start.new(name).call
    end

    desc 'restart NAME', 'Restart a Rails app'
    def restart(name)
      Commands::Restart.new(name).call
    end

    desc 'stop NAME', 'Stop a Rails app (default port 3000)'
    def stop(name)
      Commands::Stop.new(name).call
    end

    desc 'setup', 'Sets up Caddy and local trusted certificates'
    def setup
      Commands::Setup.new.call
    end

    desc 'caddy reload', 'Reloads Caddy after adding/removing apps'
    def caddy_reload
      Services::CaddyManager.reload
      puts 'Caddy reloaded'
    end

    desc 'secure DOMAIN', 'Generate trusted local HTTPS cert for a specific folder/domain'
    def secure(domain)
      apps = Services::AppRegistry.all
      app = apps.find { |a| a[:domain] == domain }
      app ||= apps.find { |a| a[:name] == domain }
      app ||= apps.find { |a| a[:domain] == "#{domain}.test" }

      unless app
        puts "No app found with domain #{domain}"
        return
      end

      Services::CaddyManager.add_app(app[:name], skip_ssl: true)
      Services::CaddyManager.reload
      puts "Secured https://#{app[:domain]}"
    end

    desc 'doctor', 'Check Stable system health'
    def doctor
      Commands::Doctor.new.call
    end

    desc 'upgrade-ruby NAME VERSION', 'Upgrade Ruby for an app'
    def upgrade_ruby(name, version)
      app = Services::AppRegistry.find(name)
      unless app
        puts "No app named #{name}"
        return
      end

      if Stable::Services::Ruby.rvm_available?
        system("bash -lc 'rvm install #{version}'")
      elsif Stable::Services::Ruby.rbenv_available?
        system("rbenv install #{version}")
      else
        puts 'No Ruby version manager found'
        return
      end

      File.write(File.join(app[:path], '.ruby-version'), version)
      Services::AppRegistry.update(name, ruby: version)

      puts "#{name} now uses Ruby #{version}"
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

    # RVM/ruby helpers moved to Services::Ruby

    def app_running?(app)
      return false unless app && app[:port]

      system("lsof -i tcp:#{app[:port]} -sTCP:LISTEN > /dev/null 2>&1")
    end

    def boot_state(app)
      return 'stopped' unless app_running?(app)

      if app[:started_at]
        elapsed = Time.now.to_i - app[:started_at]
        return "booting (#{elapsed}s)" if elapsed < 10
      end

      'running'
    end

    def dedupe_registry!
      Services::AppRegistry.dedupe
    end

    def gemset_for(app)
      Stable::Services::Ruby.gemset_for(app)
    end

    def rvm_exec(app, ruby)
      Stable::Services::Ruby.rvm_exec(app, ruby)
    end
  end
end
