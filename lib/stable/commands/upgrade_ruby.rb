# frozen_string_literal: true

require 'shellwords'

module Stable
  module Commands
    # Command for upgrading/downgrading Ruby versions for applications
    class UpgradeRuby
      def initialize(name, version)
        @name = name
        @version = version
      end

      def call
        Services::AppUpgrader.new(@name, @version).call
      end
    end
  end
end
