# frozen_string_literal: true

module Stable
  module Commands
    # Stop command - stops a Rails application
    class Stop
      def initialize(name)
        @name = name
      end

      def call
        Services::AppStopper.new(@name).call
      end
    end
  end
end
