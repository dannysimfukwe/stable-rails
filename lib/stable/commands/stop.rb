# frozen_string_literal: true

module Stable
  module Commands
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
