# frozen_string_literal: true

module Stable
  module Commands
    # Open command - opens a Rails application in a browser
    class Open
      def initialize(app_name)
        @app_name = app_name
      end

      def call
        app = Services::AppRegistry.find(@app_name)
        abort "App '#{@app_name}' not found" unless app

        abort "App '#{@app_name}' is not running" unless app[:pid] && process_alive?(app[:pid])
        url = build_url(app)
        open_browser(url)
        puts "✔ Opened #{url}"
      end

      private

      def build_url(app)
        scheme = app[:skip_ssl] ? 'http' : 'https'
        if app[:domain]
          "#{scheme}://#{app[:domain]}"
        else
          "#{scheme}://127.0.0.1:#{app[:port]}"
        end
      end

      def open_browser(url)
        cmd =
          case RbConfig::CONFIG['host_os']
          when /darwin/
            "open #{url}"
          when /linux/
            "xdg-open #{url}"
          when /mswin|mingw/
            "start #{url}"
          else
            abort 'Unsupported OS'
          end

        system(cmd) || abort('Failed to open browser')
      end

      def process_alive?(pid)
        Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end
    end
  end
end
