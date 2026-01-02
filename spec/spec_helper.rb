# frozen_string_literal: true

require 'bundler/setup'
require 'tmpdir'
require 'fileutils'

# Use a single temporary Stable root for the test run and load the library after
# overriding `Stable::Paths.root` so file paths are isolated under tmp dir.
TMP_STABLE_ROOT = Dir.mktmpdir('stable_spec')
module Stable
  module Paths
    def self.root
      TMP_STABLE_ROOT
    end
  end
end

require_relative '../lib/stable'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.before(:each) do
    # Start each example with an empty apps registry
    Stable::Registry.save([])
  end

  config.after(:suite) do
    FileUtils.rm_rf(TMP_STABLE_ROOT)
  end
end
