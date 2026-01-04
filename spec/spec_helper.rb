# frozen_string_literal: true

require 'bundler/setup'
require 'tmpdir'
require 'fileutils'

# Use a single temporary Stable root for the test run and load the library after
# setting an environment variable so file paths are isolated under tmp dir.
TMP_STABLE_ROOT = Dir.mktmpdir('stable_spec')
ENV['STABLE_TEST_ROOT'] = TMP_STABLE_ROOT

require_relative '../lib/stable'

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.before(:each) do
    # Start each example with an empty projects directory
    projects_dir = Stable::Paths.projects_dir
    FileUtils.rm_rf(projects_dir)
    FileUtils.mkdir_p(projects_dir)
  end

  config.after(:suite) do
    FileUtils.rm_rf(TMP_STABLE_ROOT)
  end
end
