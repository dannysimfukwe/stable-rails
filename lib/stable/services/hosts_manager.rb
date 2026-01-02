# frozen_string_literal: true

module Stable
  module Services
    class HostsManager
      HOSTS_FILE = '/etc/hosts'

      def self.remove(domain)
        lines = File.read(HOSTS_FILE).lines
        filtered = lines.reject { |l| l.include?(domain) }

        return if lines == filtered

        File.write('/tmp/hosts', filtered.join)
        system("sudo mv /tmp/hosts #{HOSTS_FILE}")
      end

      def self.add(domain)
        entry = "127.0.0.1\t#{domain}\n"
        hosts = File.read(HOSTS_FILE)
        return if hosts.include?(domain)

        if Process.uid.zero?
          File.open(HOSTS_FILE, 'a') { |f| f.puts entry }
        else
          system(%(echo "#{entry}" | sudo tee -a #{HOSTS_FILE} > /dev/null))
        end
      end
    end
  end
end
