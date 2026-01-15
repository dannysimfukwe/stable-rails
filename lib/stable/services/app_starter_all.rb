# frozen_string_literal: true

module Stable
  module Services
    # Service for starting all Rails applications
    class AppStarterAll
      def initialize
        @apps = AppRegistry.all
      end

      def call
        started_count = 0

        @apps.each do |app|
          if app_running?(app)
            puts "#{app[:name]} is already running on https://#{app[:domain]} (port #{app[:port]})"
          else
            start_single_app(app)
            started_count += 1
          end
        end

        if started_count.zero?
          puts 'All apps are already running'
        else
          puts "Started #{started_count} app(s)"
        end
      end

      private

      def app_running?(app)
        return false unless app

        # First check if we have PID info and if process is alive
        return ProcessManager.pid_alive?(app[:pid]) if app[:pid] && app[:started_at]

        # Fallback to port checking if no PID info available
        return false unless app[:port]

        Stable::Utils::Platform.port_in_use?(app[:port])
      end

      def start_single_app(app)
        app_starter = Services::AppStarter.new(app[:name])
        # Suppress individual output by redirecting puts temporarily
        original_stdout = $stdout
        $stdout = StringIO.new

        begin
          app_starter.call
        ensure
          $stdout = original_stdout
        end

        # Provide our own simplified output
        puts "✔ #{app[:name]} started on https://#{app[:domain]}"
      end
    end
  end
end
