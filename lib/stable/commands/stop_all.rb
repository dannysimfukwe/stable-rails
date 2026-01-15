# frozen_string_literal: true

module Stable
  module Commands
    # StopAll command - stops all Rails applications
    class StopAll
      def call
        Services::AppStopperAll.new.call
      end
    end
  end
end
