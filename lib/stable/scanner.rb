# frozen_string_literal: true

module Stable
  # Scanner utility for application discovery and management
  class Scanner
    def self.run
      Registry.save([])
    end
  end
end
