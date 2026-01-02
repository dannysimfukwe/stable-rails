# frozen_string_literal: true

module Stable
  module Commands
    class Setup
      def call
        Services::SetupRunner.new.call
      end
    end
  end
end
