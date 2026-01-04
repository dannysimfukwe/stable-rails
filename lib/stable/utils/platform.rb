# frozen_string_literal: true

module Stable
  module Utils
    module Platform
      class << self
        def macos?
          !!(RUBY_PLATFORM =~ /darwin/)
        end

        def linux?
          !!(RUBY_PLATFORM =~ /linux/)
        end

        def windows?
          !!(RUBY_PLATFORM =~ /mingw|mswin|win32/)
        end

        def unix?
          !windows?
        end

        def current
          return :macos if macos?
          return :linux if linux?
          return :windows if windows?

          :unknown
        end

        def package_manager
          return :brew if macos?
          return :apt if linux? && apt_available?
          return :yum if linux? && yum_available?
          return :pacman if linux? && pacman_available?

          :unknown
        end

        def hosts_file
          return '/etc/hosts' if unix?
          return 'C:\Windows\System32\drivers\etc\hosts' if windows?

          '/etc/hosts' # fallback
        end

        def home_directory
          return ENV.fetch('USERPROFILE', nil) if windows?

          Dir.home || Dir.home
        end

        private

        def apt_available?
          system('which apt > /dev/null 2>&1')
        end

        def yum_available?
          system('which yum > /dev/null 2>&1') || system('which dnf > /dev/null 2>&1')
        end

        def pacman_available?
          system('which pacman > /dev/null 2>&1')
        end
      end
    end
  end
end
