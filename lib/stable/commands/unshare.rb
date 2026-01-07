# frozen_string_literal: true

module Stable
  module Commands
    # Unshare app's public url
    class UnShare
      def initialize(app_name, provider: :ngrok)
        @app_name = app_name
        @provider = provider
      end

      def call
        app = Services::AppRegistry.find(@app_name)
        abort "App '#{@app_name}' not found" unless app
        Stable::Services::Rails::HostAuthorization.remove_ngrok!(app[:path])
      end
    end
  end
end
