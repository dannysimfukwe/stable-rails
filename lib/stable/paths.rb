# frozen_string_literal: true

module Stable
  module Paths
    def self.root
      ENV['STABLE_TEST_ROOT'] || File.expand_path('~/StableCaddy')
    end

    def self.caddy_dir
      root
    end

    def self.caddyfile
      File.join(caddy_dir, 'Caddyfile')
    end

    def self.certs_dir
      File.join(root, 'certs')
    end

    def self.apps_file
      File.join(root, 'apps.yml')
    end

    def self.projects_dir
      File.join(root, 'projects')
    end

    def self.app_config_file(app_name)
      File.join(projects_dir, app_name, "#{app_name}.yml")
    end
  end
end
