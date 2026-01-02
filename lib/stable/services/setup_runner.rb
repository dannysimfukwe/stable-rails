# frozen_string_literal: true

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
        path = Stable::Paths.apps_file
        File.write(path, {}.to_yaml) unless File.exist?(path)
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
        unless system('which brew > /dev/null')
          puts 'Homebrew is required. Install it first: https://brew.sh'
          exit 1
        end

        # --- Install Caddy ---
        unless system('which caddy > /dev/null')
          puts 'Installing Caddy...'
          system('brew install caddy')
        end

        # --- Install mkcert ---
        unless system('which mkcert > /dev/null')
          puts 'Installing mkcert...'
          system('brew install mkcert nss')
        end

        # Always ensure mkcert CA is installed
        system('mkcert -install')

        # --- Install PostgreSQL ---
        unless system('which psql > /dev/null')
          puts 'Installing PostgreSQL...'
          system('brew install postgresql')
          system('brew services start postgresql')
        end

        # --- Install MySQL ---
        unless system('which mysql > /dev/null')
          puts 'Installing MySQL...'
          system('brew install mysql')
          system('brew services start mysql')
        end

        puts '✅ All dependencies are installed and running.'
      end
    end
  end
end
