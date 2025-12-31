# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Stable
  class Registry
    def self.file_path
      File.join(Stable.root, 'apps.yml')
    end

    def self.save(apps)
      FileUtils.mkdir_p(Stable.root)
      File.write(file_path, apps.to_yaml)
    end

    def self.apps
      File.exist?(file_path) ? YAML.load_file(file_path) : []
    end
  end
end
