# frozen_string_literal: true

module Stable
  module Services
    # Application registry management service
    class AppRegistry
      class << self
        def all
          Stable::Registry.apps
        end

        def find(name)
          Stable::Registry.apps.find { |a| a[:name] == name }
        end

        def fetch(name)
          app = find(name)
          abort("No app found with name #{name}") unless app
          app
        end

        # Register a new app by name. If the folder already exists in the current
        # working directory it will use that path. Port is allocated sequentially.
        def register(name)
          path = File.expand_path(name)
          domain = "#{name}.test"

          used_ports = Stable::Registry.apps.map { |a| a[:port] }.compact
          port = (used_ports.max || 2999) + 1

          app = {
            name: name,
            path: path,
            domain: domain,
            port: port,
            ruby: nil,
            started_at: nil,
            pid: nil
          }

          add(app)
          app
        end

        def add(app)
          Stable::Registry.save_app_config(app[:name], app)
        end

        def remove(name)
          Stable::Registry.remove_app_config(name)
        end

        def update(name, attrs)
          app = find(name)
          return unless app

          updated_app = app.merge(attrs)

          # Check if this is a legacy app (from apps.yml) or new format app
          config_file = Stable::Paths.app_config_file(name)
          if File.exist?(config_file)
            # New format: update individual config file
            Stable::Registry.save_app_config(name, updated_app)
          else
            # Legacy format: update apps.yml file
            update_legacy_app(name, updated_app)
          end
        end

        def update_legacy_app(name, updated_app)
          legacy_file = Stable::Paths.apps_file
          return unless File.exist?(legacy_file)

          data = YAML.load_file(legacy_file) || []
          idx = data.find_index { |app| app['name'] == name || app[:name] == name }

          return unless idx

          # Convert symbols to strings for YAML compatibility
          legacy_format = updated_app.transform_keys(&:to_s)
          data[idx] = legacy_format
          File.write(legacy_file, data.to_yaml)
        end

        def mark_stopped(name)
          update(name, started_at: nil, pid: nil)
        end

        alias register_app register
        alias add_app add
      end
    end
  end
end

module Stable
  AppRegistry = Services::AppRegistry
end
