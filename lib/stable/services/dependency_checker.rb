# frozen_string_literal: true

require_relative '../utils/package_manager'

module Stable
  module Services
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
        # Check for RVM first, then rbenv, then chruby
        rvm_ok = system('which rvm > /dev/null 2>&1')
        rbenv_ok = system('which rbenv > /dev/null 2>&1')
        chruby_ok = system('which chruby > /dev/null 2>&1')

        if rvm_ok
          { name: 'RVM', ok: true, message: nil }
        elsif rbenv_ok
          { name: 'rbenv', ok: true, message: nil }
        elsif chruby_ok
          { name: 'chruby', ok: true, message: nil }
        else
          { name: 'Ruby version manager', ok: false, message: 'No Ruby version manager found (RVM, rbenv, or chruby)' }
        end
      end

      def check_caddy_running
        # Different ways to check if Caddy is running on different platforms
        platform = Stable::Utils::Platform.current

        ok = case platform
             when :macos, :linux
               system('pgrep caddy > /dev/null 2>&1')
             when :windows
               system('tasklist /FI "IMAGENAME eq caddy.exe" 2>NUL | find /I "caddy.exe" >NUL')
             else
               false
             end

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
