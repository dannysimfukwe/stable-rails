# frozen_string_literal: true

module Stable
  module Commands
    # Open command - opens a Rails application in a browser
    class Open
      def initialize(app_name)
        @app_name = app_name
      end

      def call
        Services::AppOpener.new(@app_name).call
      end
    end
  end
end
