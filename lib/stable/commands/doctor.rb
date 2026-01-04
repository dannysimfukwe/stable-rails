# frozen_string_literal: true

module Stable
  module Commands
    # Doctor command - checks system health and dependencies
    class Doctor
      def call
        puts 'Running Stable health checks...'
        puts

        checks = Services::DependencyChecker.new.run

        checks.each do |check|
          print_check(check)
        end

        puts
        summary(checks)
      end

      private

      def print_check(check)
        icon = check[:ok] ? '✔' : '✖'
        puts "#{icon} #{check[:name]}"
        puts "    #{check[:message]}" unless check[:ok]
      end

      def summary(checks)
        failures = checks.count { |c| !c[:ok] }

        if failures.zero?
          puts 'All checks passed.'
        else
          puts "#{failures} issue(s) detected. Fix the above and re-run `stable doctor`."
        end
      end
    end
  end
end
