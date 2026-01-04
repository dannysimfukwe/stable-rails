# frozen_string_literal: true

module Stable
  module Services
    # Service for stopping Rails applications
    class AppStopper
      def initialize(name)
        @app = AppRegistry.fetch(name)
      end

      def call
        ProcessManager.stop(@app)
        AppRegistry.mark_stopped(@app[:name])
        puts "✔ #{@app[:name]} stopped"
      end
    end
  end
end
