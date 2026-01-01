# frozen_string_literal: true

module Stable
  def self.root
    File.expand_path('~/.stable')
  end
end

require 'fileutils'
require_relative 'stable/paths'
require_relative 'stable/cli'
require_relative 'stable/registry'
require_relative 'stable/scanner'
require_relative 'stable/bootstrap'
require_relative 'stable/db_manager'
