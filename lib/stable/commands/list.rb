# frozen_string_literal: true

module Stable
  module Commands
    class List
      def call
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
          '%-18s %-26s %-8s %-10s %-10s',
          app[:name],
          app[:domain],
          app[:port],
          app[:ruby],
          status
        )
      end
    end
  end
end
