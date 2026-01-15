# frozen_string_literal: true

module Stable
  module Commands
    # StartAll command - starts all Rails applications
    class StartAll
      def call
        Services::AppStarterAll.new.call
      end
    end
  end
end
