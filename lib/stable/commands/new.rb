# frozen_string_literal: true

module Stable
  module Commands
    # New command - creates a new Rails application
    class New
      def initialize(name, options)
        @name = name
        @options = options
      end

      def call
        Services::AppCreator.new(@name, @options).call
      end
    end
  end
end
