# frozen_string_literal: true

module Stable
  module Commands
    # Start command - starts a Rails application
    class Start
      def initialize(name)
        @name = name
      end

      def call
        Services::AppStarter.new(@name).call
      end
    end
  end
end
