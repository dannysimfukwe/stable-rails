# frozen_string_literal: true

require 'thor'
require 'etc'
require 'tempfile'
require 'fileutils'
require 'io/console'
require_relative 'scanner'
require_relative 'registry'

module Stable
  # Main CLI class for the Stable command-line interface
  class CLI < Thor
    def initialize(*)
      super
      Stable::Bootstrap.run!
      Services::SetupRunner.ensure_dependencies!
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
    method_option :full, type: :boolean, default: false, desc: 'Setup full Rails app common generators'
    def new(name, ruby: RUBY_VERSION, rails: nil, port: nil)
      safe_name = Validators::AppName.call!(name)
      Commands::New.new(safe_name, options).call
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

    desc 'destroy NAME', 'Permanently delete a Rails app and all its files'
    def destroy(name)
      Commands::Destroy.new(name).call
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
      Stable::Utils::Platform.port_in_use?(port)
    end
  end
end
