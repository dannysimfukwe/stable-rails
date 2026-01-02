# frozen_string_literal: true

module Stable
  def self.root
    Paths.root
  end
end

require 'fileutils'
require_relative 'stable/paths'
require_relative 'stable/cli'
require_relative 'stable/registry'
require_relative 'stable/scanner'
require_relative 'stable/bootstrap'
require_relative 'stable/db_manager'

Dir[File.join(__dir__, 'stable', 'services', '**', '*.rb')].sort.each { |f| require f }
Dir[File.join(__dir__, 'stable', 'commands', '**', '*.rb')].sort.each { |f| require f }
Dir[File.join(__dir__, 'stable', 'system', '**', '*.rb')].sort.each { |f| require f }
Dir[File.join(__dir__, 'stable', 'utils', '**', '*.rb')].sort.each { |f| require f }
Dir[File.join(__dir__, 'stable', 'config', '**', '*.rb')].sort.each { |f| require f }

AppRegistry = Stable::Services::AppRegistry unless defined?(::AppRegistry)
HostsManager = Stable::Services::HostsManager unless defined?(::HostsManager)
CaddyManager = Stable::Services::CaddyManager unless defined?(::CaddyManager)
ProcessManager = Stable::Services::ProcessManager unless defined?(::ProcessManager)
AppCreator = Stable::Services::AppCreator unless defined?(::AppCreator)
AppStarter = Stable::Services::AppStarter unless defined?(::AppStarter)
AppStopper = Stable::Services::AppStopper unless defined?(::AppStopper)
AppRemover = Stable::Services::AppRemover unless defined?(::AppRemover)
Database = Stable::Services::Database unless defined?(::Database)
Ruby = Stable::Services::Ruby unless defined?(::Ruby)
Commands = Stable::Commands unless defined?(::Commands)
