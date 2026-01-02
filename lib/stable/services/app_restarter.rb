# frozen_string_literal: true

module Stable
  module Services
    class AppRestarter
      def initialize(name)
        @name = name
      end

      def call
        app = Services::AppRegistry.find(@name)
        unless app
          puts("No app found with name #{@name}")
          return
        end

        # Stop if running
        if app[:pid]
          begin
            Process.kill('TERM', app[:pid].to_i)
          rescue Errno::ESRCH
            # already dead
          end
          AppRegistry.update(@name, started_at: nil, pid: nil)
          puts "✔ #{@name} stopped"
        end

        Services::AppStarter.new(@name).call
      end
    end
  end
end
