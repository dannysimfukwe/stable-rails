# frozen_string_literal: true

module Stable
  module Commands
    class Restart
      def initialize(name)
        @name = name
      end

      def call
        Services::AppRestarter.new(@name).call
      end
    end
  end
end
