# frozen_string_literal: true

module Stable
  module System
    # Shell command execution utilities
    class Shell
      def self.run(cmd)
        puts "→ #{cmd}"
        success = system(cmd)
        raise "Command failed: #{cmd}" unless success
      end
    end
  end
end
