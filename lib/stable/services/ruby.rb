# frozen_string_literal: true

module Stable
  module Services
    module Ruby
      def self.ensure_version(version)
        return if version.nil? || version.to_s.strip.empty?

        # Check if version exists via rvm
        installed = system("bash -lc 'rvm list strings | grep -q #{version}'")
        return if installed

        puts "Installing Ruby #{version}..."
        success = system("bash -lc 'rvm install #{version}'")
        raise "Failed to install Ruby #{version}" unless success
      end

      def self.rvm_available?
        system("bash -lc 'command -v rvm > /dev/null'")
      end

      def self.rbenv_available?
        system('command -v rbenv > /dev/null')
      end

      def self.ensure_rvm!
        return if rvm_available?

        puts 'RVM not found. Installing RVM...'

        install_cmd = <<~CMD
          curl -sSL https://get.rvm.io | bash -s stable
        CMD

        abort 'RVM installation failed' unless system(install_cmd)

        rvm_script = File.expand_path('~/.rvm/scripts/rvm')
        abort 'RVM installed but could not be loaded' unless File.exist?(rvm_script)

        ENV['PATH'] = "#{File.expand_path('~/.rvm/bin')}:#{ENV['PATH']}"

        system(%(bash -lc "source #{rvm_script} && rvm --version")) || abort('RVM installed but not functional')
      end

      def self.ensure_ruby_installed!(version)
        return if system("rvm list strings | grep ruby-#{version} > /dev/null")

        puts "Installing Ruby #{version}..."
        system("rvm install #{version}") || abort("Failed to install Ruby #{version}")
      end

      def self.ensure_rvm_ruby!(version)
        system("bash -lc 'rvm list strings | grep -q #{version} || rvm install #{version}'")
      end

      def self.ensure_rbenv_ruby!(version)
        system("rbenv versions | grep -q #{version} || rbenv install #{version}")
      end

      def self.rvm_script
        File.expand_path('~/.rvm/scripts/rvm')
      end

      # Return a command prefix that sources RVM and executes the given ruby@gemset
      # Example: "source /Users/me/.rvm/scripts/rvm && rvm 3.4.4@myapp do"
      def self.rvm_prefix(ruby, gemset = nil)
        gemset_part = gemset ? "@#{gemset}" : ''
        "source #{rvm_script} && rvm #{ruby}#{gemset_part} do"
      end

      def self.detect_ruby_version(path)
        rv = File.join(path, '.ruby-version')
        return File.read(rv).strip if File.exist?(rv)

        gemfile = File.join(path, 'Gemfile')
        if File.exist?(gemfile)
          ruby_line = File.read(gemfile)[/^ruby ['"](.+?)['"]/, 1]
          return ruby_line if ruby_line
        end

        nil
      end

      def self.gemset_for(app)
        gemset_file = File.join(app[:path], '.ruby-gemset')
        return File.read(gemset_file).strip if File.exist?(gemset_file)

        nil
      end

      def self.rvm_exec(app, ruby)
        gemset = gemset_for(app)

        if gemset
          "rvm #{ruby}@#{gemset} do"
        else
          "rvm #{ruby} do"
        end
      end
    end
  end
end
