# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Stable
  class Registry
    def self.file_path
      Stable::Paths.apps_file
    end

    def self.save(apps)
      FileUtils.mkdir_p(Stable.root)
      File.write(file_path, apps.to_yaml)
    end

    def self.apps
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
  end
end
