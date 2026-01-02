# frozen_string_literal: true

module Stable
  module Services
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
          apps = Stable::Registry.apps
          apps.reject! { |a| a[:name] == app[:name] }
          apps << app
          Stable::Registry.save(apps)
        end

        # Remove duplicate app entries (by name) and persist the canonical list
        def dedupe
          apps = Stable::Registry.apps
          apps.uniq! { |a| a[:name] }
          Stable::Registry.save(apps)
          apps
        end

        def remove(name)
          apps = Stable::Registry.apps.reject { |a| a[:name] == name }
          Stable::Registry.save(apps)
        end

        def update(name, attrs)
          apps = Stable::Registry.apps
          idx = apps.index { |a| a[:name] == name }
          return unless idx

          apps[idx] = apps[idx].merge(attrs)
          Stable::Registry.save(apps)
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
