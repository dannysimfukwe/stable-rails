# frozen_string_literal: true

require_relative '../utils/platform'

module Stable
  module Services
    class HostsManager
      def self.hosts_file
        Stable::Utils::Platform.hosts_file
      end

      def self.remove(domain)
        hosts_file = hosts_file()
        lines = File.read(hosts_file).lines
        filtered = lines.reject { |l| l.include?(domain) }

        return if lines == filtered

        if Process.uid.zero?
          File.write(hosts_file, filtered.join)
        else
          File.write('/tmp/hosts', filtered.join)
          system("sudo mv /tmp/hosts #{hosts_file}")
        end
      end

      def self.add(domain)
        hosts_file = hosts_file()
        entry = "127.0.0.1\t#{domain}\n"
        hosts = File.read(hosts_file)
        return if hosts.include?(domain)

        if Process.uid.zero?
          File.open(hosts_file, 'a') { |f| f.puts entry }
        else
          system(%(echo "#{entry}" | sudo tee -a #{hosts_file} > /dev/null))
        end
      end
    end
  end
end
