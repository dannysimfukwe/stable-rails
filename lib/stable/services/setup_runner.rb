# frozen_string_literal: true

require_relative '../utils/package_manager'

module Stable
  module Services
    class SetupRunner
      def call
        ensure_directories
        ensure_apps_registry
        ensure_caddyfile
        # start or ensure caddy is running like original CLI
        Stable::Services::CaddyManager.ensure_running!
        puts "Caddy home initialized at #{Stable::Paths.root}"
        self.class.ensure_dependencies!
      end

      def self.ensure_dependencies!
        new.send(:ensure_dependencies!)
      end

      private

      def ensure_directories
        path = Stable::Paths.certs_dir
        FileUtils.mkdir_p(path)
      end

      def ensure_apps_registry
        path = Stable::Paths.projects_dir
        FileUtils.mkdir_p(path)
      end

      def ensure_caddyfile
        path = Stable::Paths.caddyfile
        return if File.exist?(path)

        File.write(path, <<~CADDY)
          {
            auto_https off
          }
        CADDY
      end

      def ensure_dependencies!
        platform = Stable::Utils::Platform.current

        unless Stable::Utils::PackageManager.available?
          puts "#{Stable::Utils::PackageManager.name} package manager is required."
          show_platform_installation_instructions(platform)
          exit 1
        end

        # --- Install Caddy ---
        unless system('which caddy > /dev/null 2>&1')
          puts 'Installing Caddy...'
          install_package('caddy')
        end

        # --- Install mkcert ---
        unless system('which mkcert > /dev/null 2>&1')
          puts 'Installing mkcert...'
          install_mkcert(platform)
        end

        # Always ensure mkcert CA is installed (skip on Windows for now)
        unless platform == :windows
          begin
            system('mkcert -install')
          rescue StandardError
            nil
          end
        end

        # --- Install PostgreSQL ---
        unless system('which psql > /dev/null 2>&1')
          puts 'Installing PostgreSQL...'
          install_postgres(platform)
        end

        # --- Install MySQL ---
        unless system('which mysql > /dev/null 2>&1')
          puts 'Installing MySQL...'
          install_mysql(platform)
        end

        puts '✅ All dependencies are installed and running.'
      end

      def install_package(package)
        cmd = Stable::Utils::PackageManager.install_command(package)
        system(cmd) or abort("Failed to install #{package}")
      end

      def install_mkcert(platform)
        case platform
        when :macos
          install_package('mkcert nss')
        when :linux
          case Stable::Utils::Platform.package_manager
          when :apt
            system('sudo apt update && sudo apt install -y wget')
            system('wget -O mkcert https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64')
            system('chmod +x mkcert && sudo mv mkcert /usr/local/bin/')
          when :yum
            system('wget -O mkcert https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64')
            system('chmod +x mkcert && sudo mv mkcert /usr/local/bin/')
          end
        when :windows
          puts 'Please install mkcert manually on Windows: https://github.com/FiloSottile/mkcert'
        end
      end

      def install_postgres(platform)
        case platform
        when :macos
          install_package('postgresql')
          begin
            system('brew services start postgresql')
          rescue StandardError
            nil
          end
        when :linux
          install_package('postgresql postgresql-contrib')
          start_service('postgresql')
        when :windows
          puts 'Please install PostgreSQL manually on Windows from: https://www.postgresql.org/download/windows/'
        end
      end

      def install_mysql(platform)
        case platform
        when :macos
          install_package('mysql')
          begin
            system('brew services start mysql')
          rescue StandardError
            nil
          end
        when :linux
          install_package('mysql-server')
          start_service('mysql')
        when :windows
          puts 'Please install MySQL manually on Windows from: https://dev.mysql.com/downloads/mysql/'
        end
      end

      def start_service(service)
        cmd = Stable::Utils::PackageManager.service_start_command(service)
        begin
          system(cmd)
        rescue StandardError
          nil
        end
      end

      def show_platform_installation_instructions(platform)
        case platform
        when :macos
          puts 'Homebrew is required. Install it first: https://brew.sh'
        when :linux
          puts 'Please install a package manager:'
          puts '  Ubuntu/Debian: sudo apt update && sudo apt install -y build-essential'
          puts '  CentOS/RHEL: sudo yum install -y gcc gcc-c++ make'
          puts '  Arch: sudo pacman -S base-devel'
        when :windows
          puts 'Please install dependencies manually on Windows.'
          puts 'Required: Caddy, mkcert, PostgreSQL, MySQL'
        else
          puts 'Unsupported platform detected.'
        end
      end
    end
  end
end
