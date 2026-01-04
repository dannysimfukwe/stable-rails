# frozen_string_literal: true

require_relative 'platform'

module Stable
  module Utils
    # Cross-platform package manager utilities
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
            "sudo systemctl start #{service}" if systemctl_available?
          else
            raise "Service management not supported on #{Platform.current} platform"
          end
        end

        def available?
          pm = Platform.package_manager
          if pm == :yum
            system('which yum > /dev/null 2>&1') || system('which dnf > /dev/null 2>&1')
          else
            cmd = package_manager_commands.dig(pm, 0)
            cmd ? system("#{cmd} > /dev/null 2>&1") : false
          end
        end

        def name
          pm = Platform.package_manager
          package_manager_commands[pm]&.last || 'Unknown'
        end

        private

        def package_manager_commands
          {
            brew: ['which brew', 'Homebrew'],
            apt: ['which apt', 'APT'],
            yum: ['which yum', 'YUM/DNF'],
            pacman: ['which pacman', 'Pacman']
          }
        end

        def systemctl_available?
          system('which systemctl > /dev/null 2>&1')
        end
      end
    end
  end
end
