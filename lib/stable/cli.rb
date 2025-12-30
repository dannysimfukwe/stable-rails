require "thor"
require "etc"
require "fileutils"
require_relative "scanner"
require_relative "registry"

module Stable
  class CLI < Thor

    HOSTS_FILE = "/etc/hosts".freeze

    def initialize(*)
      super
      Stable::Bootstrap.run!
      ensure_dependencies!
    end
    def self.exit_on_failure?
      true
    end

    desc "list", "List detected apps"
    def list
      apps = Registry.apps
      if apps.empty?
        puts "No apps found."
      else
        apps.each do |app|
          puts "#{app[:name]} -> https://#{app[:domain]}"
        end
      end
    end

    desc "add FOLDER", "Add a Rails app folder"
    def add(folder)
      folder = File.expand_path(folder)
      unless File.exist?(File.join(folder, "config", "application.rb"))
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

      apps << { name: name, path: folder, domain: domain, port: port }
      Registry.save(apps)
      puts "Added #{name} -> https://#{domain} (port #{port})"

      add_host_entry(domain)
      generate_cert(domain)
      update_caddyfile(domain, port)
      caddy_reload
    end

    desc "remove NAME", "Remove an app by name"
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

    desc "start NAME", "Start a Rails app (default port 3000) and ensure Caddy proxy"
    def start(name)
      app = Registry.apps.find { |a| a[:name] == name }
      unless app
        puts "No app found with name #{name}"
        return
      end

      port = app[:port] || next_free_port
      puts "Starting Rails server for #{name} on port #{port}..."

      log_file = File.join(app[:path], "log", "stable.log")
      FileUtils.mkdir_p(File.dirname(log_file))
      pid = spawn("cd #{app[:path]} && bundle exec rails s -p #{port} >> #{log_file} 2>&1")
      Process.detach(pid)
      puts "Rails logs are in #{log_file}"

      generate_cert(app[:domain])
      update_caddyfile(app[:domain], port)
      wait_for_port(port)
      caddy_reload
    end

    desc "stop NAME", "Stop a Rails app (default port 3000)"
    def stop(name)
      app = Registry.apps.find { |a| a[:name] == name }

      output = `lsof -i tcp:#{app[:port]} -t`.strip
      if output.empty?
        puts "No app running on port #{app[:port]}"
      else
        output.split("\n").each { |pid| Process.kill("TERM", pid.to_i) }
        puts "Stopped #{name}"
      end
    end

    desc "setup", "Sets up Caddy and local trusted certificates"
    def setup
      FileUtils.mkdir_p(Stable::Paths.root)
      File.write(Stable::Paths.caddyfile, "") unless File.exist?(Stable::Paths.caddyfile)
      ensure_caddy_running!
      puts "Caddy home initialized at #{Stable::Paths.root}"
    end

    desc "caddy reload", "Reloads Caddy after adding/removing apps"

    def caddy_reload
      if system("which caddy > /dev/null")
        system("caddy reload --config #{Stable::Paths.caddyfile}")
        puts "Caddy reloaded"
      else
        puts "Caddy not found. Install Caddy first."
      end
    end

    desc "secure DOMAIN", "Generate trusted local HTTPS cert for a specific folder/domain"
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

    private

    def add_host_entry(domain)
      entry = "127.0.0.1\t#{domain}"
      hosts = File.read(HOSTS_FILE)
      unless hosts.include?(domain)
        puts "Adding #{domain} to #{HOSTS_FILE}..."
        File.open(HOSTS_FILE, "a") { |f| f.puts entry }
        system("dscacheutil -flushcache; sudo killall -HUP mDNSResponder")
      end
    rescue Errno::EACCES
      ensure_hosts_entry(domain)
    end

    def remove_host_entry(domain)
      begin
        hosts = File.read(HOSTS_FILE)
        new_hosts = hosts.lines.reject { |line| line.include?(domain) }.join
        File.write(HOSTS_FILE, new_hosts)
        system("dscacheutil -flushcache; sudo killall -HUP mDNSResponder")
      rescue Errno::EACCES
        puts "Permission denied updating #{HOSTS_FILE}. Run 'sudo stable remove #{domain}' to remove hosts entry."
      end
    end

    def ensure_hosts_entry(domain)
      entry = "127.0.0.1\t#{domain}"

      hosts = File.read(HOSTS_FILE)
      return if hosts.include?(domain)

      if Process.uid.zero?
        File.open(HOSTS_FILE, "a") { |f| f.puts entry }
      else
        system(%(echo "#{entry}" | sudo tee -a #{HOSTS_FILE} > /dev/null))
      end

      system("dscacheutil -flushcache; sudo killall -HUP mDNSResponder")
    end

    def secure_app(domain, _folder, port)
      ensure_certs_dir! 

      cert_path = File.join(Stable::Paths.certs_dir, "#{domain}.pem")
      key_path  = File.join(Stable::Paths.certs_dir, "#{domain}-key.pem")

      # Generate certificates if missing
      if system("which mkcert > /dev/null")
        unless File.exist?(cert_path) && File.exist?(key_path)
          system("mkcert -cert-file #{cert_path} -key-file #{key_path} #{domain}")
        end
      else
        puts "mkcert not found. Please install mkcert."
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
      new_content = content.gsub(/https:\/\/#{Regexp.escape(domain)}\s*\{[^\}]*\}/m, "")
      File.write(Stable::Paths.caddyfile, new_content)
    end

    def ensure_dependencies!
      unless system("which brew > /dev/null")
        puts "Homebrew is required. Install it first: https://brew.sh"
        exit 1
      end

      unless system("which caddy > /dev/null")
        puts "Installing Caddy..."
        system("brew install caddy")
      end

      unless system("which mkcert > /dev/null")
        puts "Installing mkcert..."
        system("brew install mkcert nss")
        system("mkcert -install")
      end
    end
    def ensure_caddy_running!
      api_port = 2019

      # Check if Caddy API is reachable
      require 'socket'
      begin
        TCPSocket.new('127.0.0.1', api_port).close
        puts "Caddy already running."
      rescue Errno::ECONNREFUSED
        puts "Starting Caddy in background..."
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

      unless File.exist?(cert_path) && File.exist?(key_path)
        if system("which mkcert > /dev/null")
          system("mkcert -cert-file #{cert_path} -key-file #{key_path} #{domain}")
        else
          puts "mkcert not found. Please install mkcert."
        end
      end
    end

    def update_caddyfile(domain, port)
      caddyfile = Stable::Paths.caddyfile
      FileUtils.touch(caddyfile) unless File.exist?(caddyfile)
      content = File.read(caddyfile)

      # remove existing block for domain
      content.gsub!(/https:\/\/#{Regexp.escape(domain)}\s*\{[^\}]*\}/m, "")

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
      rescue => e
        puts "Could not change ownership: #{e.message}"
      end

      # Restrict permissions for security
      Dir.glob("#{certs_dir}/*.pem").each do |pem|
        FileUtils.chmod(0600, pem)
      end
    end

    def wait_for_port(port, timeout: 5)
      require 'socket'
      start_time = Time.now
      loop do
        begin
          TCPSocket.new('127.0.0.1', port).close
          break
        rescue Errno::ECONNREFUSED
          raise "Timeout waiting for port #{port}" if Time.now - start_time > timeout
          sleep 0.1
        end
      end
    end
  end
end
