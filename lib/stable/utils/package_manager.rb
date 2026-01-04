# frozen_string_literal: true

require_relative 'platform'

module Stable
  module Utils
    module PackageManager
      class << self
        def install_command(package)
          case Platform.package_manager
          when :brew
            "brew install #{package}"
          when :apt
            "sudo apt update && sudo apt install -y #{package}"
          when :yum
            "sudo yum install -y #{package}"
          when :pacman
            "sudo pacman -S --noconfirm #{package}"
          else
            raise "Unsupported package manager on #{Platform.current} platform"
          end
        end

        def service_start_command(service)
          case Platform.current
          when :macos
            "brew services start #{service}"
          when :linux
            if Platform.package_manager == :apt
              "sudo systemctl start #{service}" if systemctl_available?
            elsif Platform.package_manager == :yum
              "sudo systemctl start #{service}" if systemctl_available?
            end
          else
            raise "Service management not supported on #{Platform.current} platform"
          end
        end

        def available?
          case Platform.package_manager
          when :brew
            system('which brew > /dev/null 2>&1')
          when :apt
            system('which apt > /dev/null 2>&1')
          when :yum
            system('which yum > /dev/null 2>&1') || system('which dnf > /dev/null 2>&1')
          when :pacman
            system('which pacman > /dev/null 2>&1')
          else
            false
          end
        end

        def name
          case Platform.package_manager
          when :brew
            'Homebrew'
          when :apt
            'APT'
          when :yum
            'YUM/DNF'
          when :pacman
            'Pacman'
          else
            'Unknown'
          end
        end

        private

        def systemctl_available?
          system('which systemctl > /dev/null 2>&1')
        end
      end
    end
  end
end
