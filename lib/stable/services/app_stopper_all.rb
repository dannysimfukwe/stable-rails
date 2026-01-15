# frozen_string_literal: true

module Stable
  module Services
    # Service for stopping all Rails applications
    class AppStopperAll
      def initialize
        @apps = AppRegistry.all
      end

      def call
        stopped_count = 0

        @apps.each do |app|
          next unless app_running?(app)

          ProcessManager.stop(app)
          AppRegistry.mark_stopped(app[:name])
          puts "✔ #{app[:name]} stopped"
          stopped_count += 1
        end

        if stopped_count.zero?
          puts 'No running apps found'
        else
          puts "Stopped #{stopped_count} app(s)"
        end
      end

      private

      def app_running?(app)
        return false unless app[:port]

        Stable::Utils::Platform.find_pids_by_port(app[:port]).any?
      end
    end
  end
end
