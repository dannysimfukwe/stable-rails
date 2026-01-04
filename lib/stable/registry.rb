# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Stable
  # Application registry for managing Rails app configurations
  class Registry
    def self.apps
      apps = []

      # Read legacy apps.yml file for backward compatibility
      legacy_file = Stable::Paths.apps_file
      if File.exist?(legacy_file)
        legacy_apps = load_legacy_apps(legacy_file)
        apps.concat(legacy_apps)
      end

      # Read individual app config files from projects directory
      projects_dir = Stable::Paths.projects_dir
      if Dir.exist?(projects_dir)
        Dir.glob(File.join(projects_dir, '*/')).each do |app_dir|
          app_name = File.basename(app_dir)
          config_file = Stable::Paths.app_config_file(app_name)

          next unless File.exist?(config_file)

          # Skip if we already have this app from legacy file
          next if apps.any? { |app| app[:name] == app_name }

          app_config = load_app_config(app_name)
          apps << app_config if app_config
        end
      end

      apps
    end

    def self.load_legacy_apps(file_path)
      return [] unless File.exist?(file_path)

      data = YAML.load_file(file_path) || []
      data.map do |entry|
        next entry unless entry.is_a?(Hash)

        entry.each_with_object({}) do |(k, v), memo|
          key = k.is_a?(String) ? k.to_sym : k
          memo[key] = v
        end
      end
    end

    def self.save_app_config(app_name, config)
      config_file = Stable::Paths.app_config_file(app_name)
      FileUtils.mkdir_p(File.dirname(config_file))
      File.write(config_file, config.to_yaml)
    end

    def self.load_app_config(app_name)
      config_file = Stable::Paths.app_config_file(app_name)
      return nil unless File.exist?(config_file)

      parse_config_file(config_file)
    end

    def self.remove_app_config(app_name)
      config_file = Stable::Paths.app_config_file(app_name)
      FileUtils.rm_f(config_file)

      # Also remove from legacy apps.yml file for backward compatibility
      remove_from_legacy_file(app_name)
    end

    def self.remove_from_legacy_file(app_name)
      legacy_file = Stable::Paths.apps_file
      return unless File.exist?(legacy_file)

      data = YAML.load_file(legacy_file) || []
      filtered_data = data.reject { |entry| entry.is_a?(Hash) && entry['name'] == app_name }

      return unless filtered_data != data

      File.write(legacy_file, filtered_data.to_yaml)
    end

    def self.parse_config_file(config_file)
      data = YAML.load_file(config_file)
      return nil unless data.is_a?(Hash)

      data.each_with_object({}) do |(k, v), memo|
        key = k.is_a?(String) ? k.to_sym : k
        memo[key] = v
      end
    end
  end
end
