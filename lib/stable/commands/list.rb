# frozen_string_literal: true

module Stable
  module Commands
    # List command - displays all registered applications
    class List
    def call
      # Validate and clean up stale app statuses
      Services::ProcessManager.validate_app_statuses

      apps = Services::AppRegistry.all

      if apps.empty?
        puts 'No apps registered.'
        return
      end

      print_header

      apps.each do |app|
        puts format_row(app)
      end
    end

      private

      def print_header
        puts 'APP                DOMAIN                     PORT     RUBY       STATUS    '
        puts '-' * 78
      end

      def format_row(app)
        status =
          if app[:started_at]
            'running'
          else
            'stopped'
          end

        format(
          '%<name>-18s %<domain>-26s %<port>-8s %<ruby>-10s %<status>-10s',
          name: app[:name],
          domain: app[:domain],
          port: app[:port],
          ruby: app[:ruby],
          status: status
        )
      end
    end
  end
end
