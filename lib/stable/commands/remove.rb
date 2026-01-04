# frozen_string_literal: true

module Stable
  module Commands
    # Remove command - removes a Rails application
    class Remove
      def initialize(name)
        @name = name
      end

      def call
        app = Services::AppRegistry.find(@name)
        abort 'App not found' unless app

        Services::ProcessManager.stop(app)
        Services::HostsManager.remove(app[:domain])
        Services::CaddyManager.remove(app[:domain])
        Services::AppRegistry.remove(@name)
        Services::CaddyManager.reload

        puts "Removed #{@name}"
      end
    end
  end
end
