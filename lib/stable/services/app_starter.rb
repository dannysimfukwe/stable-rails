# frozen_string_literal: true

module Stable
  module Services
    # Service for starting Rails applications
    class AppStarter
      def initialize(name)
        @name = name
      end

      def call
        app = Services::AppRegistry.find(@name)
        unless app
          puts("No app found with name #{@name}")
          return
        end

        port = app[:port] || next_free_port
        ruby = app[:ruby]
        path = app[:path]

        if app_running?(app)
          puts "#{@name} is already running on https://#{app[:domain]} (port #{port})"
          # Update the registry with the correct PID if it's missing
          if !app[:pid] || !app[:started_at]
            rails_pid = find_rails_pid(port)
            if rails_pid
              AppRegistry.update(app[:name], started_at: Time.now.to_i, pid: rails_pid)
              puts "Updated registry with correct PID (#{rails_pid})"
            end
          end
          return
        end

        gemset = Stable::Services::Ruby.gemset_for(app)

        rvm_cmd =
          if ruby && gemset
            System::Shell.run("bash -lc 'source #{Stable::Services::Ruby.rvm_script} && rvm #{ruby}@#{gemset} --create do true'")
            Stable::Services::Ruby.rvm_prefix(ruby, gemset)
          elsif ruby
            Stable::Services::Ruby.rvm_prefix(ruby, nil)
          end

        puts "Starting #{@name} on port #{port}..."

        log_file = File.join(path, 'log', 'stable.log')
        FileUtils.mkdir_p(File.dirname(log_file))

        pid = spawn(
          'bash',
          '-lc',
          "cd \"#{path}\" && #{rvm_cmd} bundle exec rails s -p #{port} -b 127.0.0.1",
          out: log_file,
          err: log_file
        ).to_i

        Process.detach(pid)

        wait_for_port(port, timeout: 30)

        # Find the actual Rails process PID by checking what's listening on the port
        rails_pid = find_rails_pid(port)
        AppRegistry.update(app[:name], started_at: Time.now.to_i, pid: rails_pid)

        Stable::Services::CaddyManager.add_app(app[:name], skip_ssl: false)
        Stable::Services::CaddyManager.reload

        puts "#{@name} started on https://#{app[:domain]}"
      end

      private

      def next_free_port
        used_ports = Services::AppRegistry.all.map { |a| a[:port] }
        port = 3000
        port += 1 while used_ports.include?(port) || port_in_use?(port)
        port
      end

      def port_in_use?(port)
        Stable::Utils::Platform.port_in_use?(port)
      end

      def wait_for_port(port, timeout: 20)
        require 'socket'
        start = Time.now

        loop do
          TCPSocket.new('127.0.0.1', port).close
          return
        rescue Errno::ECONNREFUSED
          raise "Rails never bound port #{port}. Check log/stable.log" if Time.now - start > timeout

          sleep 0.5
        end
      end

      def app_running?(app)
        return false unless app

        # First check if we have PID info and if the process is alive
        return ProcessManager.pid_alive?(app[:pid]) if app[:pid] && app[:started_at]

        # Fallback to port checking if no PID info available
        return false unless app[:port]

        Stable::Utils::Platform.port_in_use?(app[:port])
      end

      def find_rails_pid(port)
        pids = Stable::Utils::Platform.find_pids_by_port(port)
        pids.first
      end
    end
  end
end
