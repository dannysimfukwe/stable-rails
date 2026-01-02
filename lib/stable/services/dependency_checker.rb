# frozen_string_literal: true

module Stable
  module Services
    class DependencyChecker
      def run
        [
          check('Homebrew', 'brew'),
          check('Caddy', 'caddy'),
          check('mkcert', 'mkcert'),
          check('RVM', 'rvm'),
          check_caddy_running,
          check_certs_dir,
          check_apps_registry
        ]
      end

      private

      def check(name, command)
        ok = system("which #{command} > /dev/null 2>&1")
        {
          name: name,
          ok: ok,
          message: ok ? nil : "#{name} not found in PATH"
        }
      end

      def check_caddy_running
        ok = system('pgrep caddy > /dev/null 2>&1')
        {
          name: 'Caddy running',
          ok: ok,
          message: ok ? nil : 'Caddy is installed but not running'
        }
      end

      def check_certs_dir
        path = File.expand_path('~/StableCaddy/certs')
        ok = Dir.exist?(path)
        {
          name: 'Certificates directory',
          ok: ok,
          message: ok ? nil : "Missing #{path}. Run `stable setup`"
        }
      end

      def check_apps_registry
        path = File.expand_path('~/StableCaddy/apps.yml')
        ok = File.exist?(path)
        {
          name: 'Apps registry',
          ok: ok,
          message: ok ? nil : 'Missing apps registry. Run `stable setup`'
        }
      end
    end
  end
end
