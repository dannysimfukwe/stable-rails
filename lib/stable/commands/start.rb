# frozen_string_literal: true

module Stable
  module Commands
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
