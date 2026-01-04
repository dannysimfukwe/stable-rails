# frozen_string_literal: true

require 'io/console'

module Stable
  module Utils
    # User interaction utilities for prompting input
    class Prompts
      def self.mysql_root_credentials
        print 'Enter MySQL root username (default: root): '
        user = $stdin.gets.strip
        user = 'root' if user.empty?

        print 'Enter MySQL root password (leave blank if none): '
        password = $stdin.noecho(&:gets).chomp
        puts

        { user: user, password: password }
      end
    end
  end
end
