# frozen_string_literal: true

module Stable
  module Commands
    # Share app's public url
    class Share
      def initialize(app_name, provider: :ngrok, qrcode: false)
        @app_name = app_name
        @provider = provider
        @qrcode   = qrcode
      end

      def call
        app = Services::AppRegistry.find(@app_name)
        abort "App '#{@app_name}' not found" unless app
        abort "App '#{@app_name}' is not running" unless running?(app)
        Services::Rails::HostAuthorization.allow_ngrok!(app[:path])
        Services::ProcessManager.stop(app) # stop the app
        Services::ProcessManager.start(app) # restart the app

        # Pass the real app port here
        url = Services::Tunneling::Manager
              .new(provider: @provider)
              .expose_domain(app[:domain], port: app[:port], skip_ssl: app[:skip_ssl])

        puts "🌐 Shared #{@app_name} at:"
        puts "   #{url}"

        return unless @qrcode

        Services::Cli::QrCode.print(url)
      end

      private

      def running?(app)
        Process.kill(0, app[:pid])
        true
      rescue Errno::ESRCH
        false
      end
    end
  end
end
