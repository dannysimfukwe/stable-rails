# frozen_string_literal: true

module Stable
  module Services
    # Service for managing application processes
    class ProcessManager
      def self.start(target)
        app = target.is_a?(String) ? AppRegistry.fetch(target) : target

        path = app[:path]
        port = app[:port]

        ruby = app[:ruby]
        gemset = Stable::Services::Ruby.gemset_for(app)

        if ruby && gemset
          Stable::Services::Ruby.ensure_rvm!
          system("bash -lc 'rvm #{ruby}@#{gemset} --create do true'")
          rvm_cmd = "rvm #{ruby}@#{gemset} do"
        elsif ruby
          rvm_cmd = "rvm #{ruby} do"
        else
          rvm_cmd = nil
        end

        log_file = File.join(path, 'log', 'stable.log')
        FileUtils.mkdir_p(File.dirname(log_file))

        cmd = if rvm_cmd
                "cd \"#{path}\" && #{rvm_cmd} bundle exec rails s -p #{port} -b 127.0.0.1"
              else
                "cd \"#{path}\" && bundle exec rails s -p #{port} -b 127.0.0.1"
              end

        pid = spawn('bash', '-lc', cmd, out: log_file, err: log_file)

        Process.detach(pid)

        AppRegistry.update(app[:name], started_at: Time.now.to_i, pid: pid)

        pid
      end

      def self.stop(app)
        pid = app[:pid]
        return unless pid

        output = `lsof -i tcp:#{app[:port]} -t`.strip
        if output.empty?
          puts "No app running on port #{app[:port]}"
        else
          output.split("\n").each { |pid| Process.kill('TERM', pid.to_i) }
          puts "Stopped #{app[:name]} on port #{app[:port]}"
        end

        AppRegistry.update(app[:name], started_at: nil, pid: nil)
      rescue Errno::ESRCH
        AppRegistry.update(app[:name], started_at: nil, pid: nil)
      end

      # Check if a process with the given PID is still running
      def self.pid_alive?(pid)
        return false unless pid

        # Use a cross-platform method to check if PID exists
        if RUBY_PLATFORM =~ /mingw|mswin|win32/
          # Windows: use tasklist
          system("tasklist /FI \"PID eq #{pid}\" 2>NUL | find /I \"#{pid}\" >NUL")
        else
          # Unix-like systems: check /proc or use ps
          begin
            Process.kill(0, pid)
            true
          rescue Errno::ESRCH
            false
          rescue Errno::EPERM
            # Process exists but we don't have permission to signal it
            true
          end
        end
      end

      # Validate and clean up stale app statuses
      def self.validate_app_statuses
        apps = AppRegistry.all
        apps.each do |app|
          next unless app[:started_at] && app[:pid]

          unless pid_alive?(app[:pid])
            AppRegistry.update(app[:name], started_at: nil, pid: nil)
          end
        end
      end
    end
  end
end
