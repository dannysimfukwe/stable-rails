# frozen_string_literal: true

require_relative '../utils/platform'

module Stable
  module Commands
    # List command - displays all registered applications
    class List
    def call
      apps = Services::AppRegistry.all

      if apps.empty?
        puts 'No apps registered.'
        return
      end

      print_header

      apps.each do |app|
        # Determine status based on whether the app is actually running (port check)
        status = app_running?(app) ? 'running' : 'stopped'
        puts format_row(app, status)
      end
    end

    private

    def app_running?(app)
      return false unless app && app[:port]

      # Check if something is listening on the app's port (cross-platform)
      Stable::Utils::Platform.port_in_use?(app[:port])
    end

    def format_row(app, status)
      format(
        '%<name>-18s %<domain>-26s %<port>-8s %<ruby>-10s %<status>-10s',
        name: app[:name],
        domain: app[:domain],
        port: app[:port],
        ruby: app[:ruby],
        status: status
      )
    end

    def print_header
      puts 'APP                DOMAIN                     PORT     RUBY       STATUS    '
      puts '-' * 78
    end
    end
  end
end
