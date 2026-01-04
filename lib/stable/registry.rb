# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Stable
  class Registry
    def self.apps
      projects_dir = Stable::Paths.projects_dir
      return [] unless Dir.exist?(projects_dir)

      Dir.glob(File.join(projects_dir, '*/')).map do |app_dir|
        app_name = File.basename(app_dir)
        config_file = Stable::Paths.app_config_file(app_name)

        next unless File.exist?(config_file)

        load_app_config(config_file)
      end.compact
    end

    def self.save_app_config(app_name, config)
      config_file = Stable::Paths.app_config_file(app_name)
      FileUtils.mkdir_p(File.dirname(config_file))
      File.write(config_file, config.to_yaml)
    end

    def self.load_app_config(app_name)
      config_file = Stable::Paths.app_config_file(app_name)
      return nil unless File.exist?(config_file)

      load_app_config(config_file)
    end

    def self.remove_app_config(app_name)
      config_file = Stable::Paths.app_config_file(app_name)
      FileUtils.rm_f(config_file)
    end

    def self.load_app_config(config_file)
      data = YAML.load_file(config_file)
      return nil unless data.is_a?(Hash)

      data.each_with_object({}) do |(k, v), memo|
        key = k.is_a?(String) ? k.to_sym : k
        memo[key] = v
      end
    end
  end
end
