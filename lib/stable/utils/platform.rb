# frozen_string_literal: true

module Stable
  module Utils
    # Platform detection utilities for cross-platform compatibility
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
          return detect_linux_package_manager if linux?

          :unknown
        end

        def hosts_file
          return '/etc/hosts' if unix?
          return 'C:\Windows\System32\drivers\etc\hosts' if windows?

          '/etc/hosts' # fallback
        end

        def home_directory
          return ENV.fetch('USERPROFILE', nil) if windows?

          Dir.home
        end

        def port_in_use?(port)
          case current
          when :macos, :linux
            # Use lsof on Unix-like systems
            system("lsof -i tcp:#{port} -sTCP:LISTEN > /dev/null 2>&1")
          when :windows
            # Use netstat on Windows
            system("netstat -an | findstr :#{port} > nul 2>&1")
          else
            false
          end
        end

        def find_pids_by_port(port)
          case current
          when :macos, :linux
            # Use lsof to find PIDs listening on the port
            output = `lsof -i tcp:#{port} -sTCP:LISTEN -t 2>/dev/null`.strip
            return [] if output.empty?
            output.split("\n").map(&:to_i)
          when :windows
            # On Windows, this is more complex. For now, return empty array
            # Could potentially parse netstat output in the future
            []
          else
            []
          end
        end

        private

        def detect_linux_package_manager
          return :apt if apt_available?
          return :yum if yum_available?
          return :pacman if pacman_available?

          :unknown
        end

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
