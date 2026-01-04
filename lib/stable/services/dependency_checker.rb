# frozen_string_literal: true

require_relative '../utils/package_manager'

module Stable
  module Services
    # Service for checking system dependencies and health
    class DependencyChecker
      def run
        platform = Stable::Utils::Platform.current
        package_manager_name = Stable::Utils::PackageManager.name

        checks = [
          check(package_manager_name, package_manager_command(platform)),
          check('Caddy', 'caddy'),
          check('mkcert', 'mkcert'),
          check_ruby_manager,
          check_caddy_running,
          check_certs_dir,
          check_apps_registry
        ]

        checks.compact
      end

      private

      def check(name, command)
        return nil if command.nil? # Skip checks that don't apply to this platform

        ok = system("which #{command} > /dev/null 2>&1")
        {
          name: name,
          ok: ok,
          message: ok ? nil : "#{name} not found in PATH"
        }
      end

      def package_manager_command(platform)
        case platform
        when :macos
          'brew'
        when :linux
          case Stable::Utils::Platform.package_manager
          when :apt
            'apt'
          when :yum
            'yum'
          when :pacman
            'pacman'
          end
        when :windows
          nil # No package manager check for Windows
        end
      end

      def check_ruby_manager
        managers = [%w[rvm RVM], %w[rbenv rbenv], %w[chruby chruby]]

        manager = managers.find do |cmd, _name|
          system("which #{cmd} > /dev/null 2>&1")
        end

        if manager
          { name: manager[1], ok: true, message: nil }
        else
          { name: 'Ruby version manager', ok: false, message: 'No Ruby version manager found (RVM, rbenv, or chruby)' }
        end
      end

      def check_caddy_running
        platform = Stable::Utils::Platform.current
        cmd = if platform == :windows
                'tasklist /FI "IMAGENAME eq caddy.exe" 2>NUL | find /I "caddy.exe" >NUL'
              else
                'pgrep caddy > /dev/null 2>&1'
              end

        ok = system(cmd)
        {
          name: 'Caddy running',
          ok: ok,
          message: ok ? nil : 'Caddy is installed but not running'
        }
      end

      def check_certs_dir
        path = Stable::Paths.certs_dir
        ok = Dir.exist?(path)
        {
          name: 'Certificates directory',
          ok: ok,
          message: ok ? nil : "Missing #{path}. Run `stable setup`"
        }
      end

      def check_apps_registry
        path = Stable::Paths.projects_dir
        ok = Dir.exist?(path)
        {
          name: 'Projects directory',
          ok: ok,
          message: ok ? nil : 'Missing projects directory. Run `stable setup`'
        }
      end
    end
  end
end
