# frozen_string_literal: true

module Stable
  module Services
    class AppRemover
      def initialize(name)
        @name = name
      end

      def call
        app = AppRegistry.fetch(@name)
        ProcessManager.stop(app)
        HostsManager.remove(app[:domain])
        CaddyManager.remove(app[:domain])
        AppRegistry.remove(@name)
        CaddyManager.reload
        puts "✔ #{@name} removed"
      end
    end
  end
end
