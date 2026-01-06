# frozen_string_literal: true

require 'io/console'

module Stable
  module Commands
    # Destroy command - permanently deletes a Rails application with confirmation
    class Destroy
      def initialize(name)
        @name = name
      end

      def call
        Services::AppDestroyer.new(@name).call
      end
    end
  end
end
