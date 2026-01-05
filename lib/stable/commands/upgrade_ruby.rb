# frozen_string_literal: true

require 'shellwords'

module Stable
  module Commands
    # Command for upgrading/downgrading Ruby versions for applications
    class UpgradeRuby
      def initialize(name, version)
        @name = name
        @version = version
      end

      def call
        app = Services::AppRegistry.find(@name)
        unless app
          puts "No app named #{@name}"
          return
        end

        current_version = app[:ruby] || RUBY_VERSION

        puts "#{action(current_version, @version)} #{@name} from Ruby #{current_version} to #{@version}..."
        puts ''

        # Install the target Ruby version if needed
        platform = Stable::Utils::Platform.current

        if platform == :windows
          puts '⚠️  Windows detected - Ruby version managers work differently on Windows'
          puts "   Please manually install Ruby #{@version} using RubyInstaller or your preferred method"
          puts '   Recommended: https://rubyinstaller.org/'
          puts '   Then update your PATH to use the new Ruby version'
          puts ''
          puts "After installing Ruby #{@version}, update the app configuration manually:"
          puts "   - Edit .ruby-version file to contain: #{@version}"
          puts '   - Run: bundle install (in the app directory)'
          return
        end

        if Stable::Services::Ruby.rvm_available?
          puts "Ensuring Ruby #{@version} is available..."
          system("bash -lc 'rvm install #{@version}'") unless ENV['STABLE_TEST_MODE']
        elsif Stable::Services::Ruby.rbenv_available?
          puts "Ensuring Ruby #{@version} is available..."
          system("rbenv install #{@version}") unless ENV['STABLE_TEST_MODE']
        else
          puts '❌ No supported Ruby version manager found'
          puts '   On macOS/Linux, install RVM (https://rvm.io/) or rbenv (https://github.com/rbenv/rbenv)'
          puts '   On Windows, use RubyInstaller (https://rubyinstaller.org/)'
          return
        end

        # Clean, simple approach: Remove current Ruby environment and install new one fresh
        puts "🔄 Upgrading #{@name} from Ruby #{current_version} to #{@version}..."

        # 1. Remove current Ruby version/gemset (like destroy command)
        cleanup_rvm_gemset(app)

        # 2. Install new Ruby version fresh (like app creator)
        setup_new_ruby_version(app, @version)

        puts ''
        puts "✅ #{@name} #{past_tense_action(action(current_version, @version))} to Ruby #{@version}!"
        puts "   Old gemset cleared, fresh #{@version}@#{@name} gemset created with gems"
        puts ''
        puts "Start with: stable start #{@name}"
      end

      private

      def cleanup_rvm_gemset(app)
        # Skip RVM operations in test mode
        return if ENV['STABLE_TEST_MODE']

        # Only clean up RVM gemsets on Unix-like systems (macOS/Linux)
        # Windows uses different Ruby version managers
        return unless Stable::Utils::Platform.unix?

        ruby_version = app[:ruby]
        # Handle different ruby version formats (e.g., "3.4.7", "ruby-3.4.7")
        clean_ruby_version = ruby_version.to_s.sub(/^ruby-/, '')
        gemset_name = "#{clean_ruby_version}@#{@name}"

        puts "   Cleaning up RVM gemset #{gemset_name}..."
        begin
          # Use system to run RVM command to delete the gemset
          system("bash -lc 'source ~/.rvm/scripts/rvm && rvm gemset delete #{gemset_name} --force' 2>/dev/null || true")
          puts "   ✅ RVM gemset #{gemset_name} cleaned up"
        rescue StandardError => e
          puts "   ⚠️  Could not clean up RVM gemset #{gemset_name}: #{e.message}"
        end
      end

      def setup_new_ruby_version(app, new_version)
        # Follow app_creator.rb pattern exactly
        unless ENV['STABLE_TEST_MODE']
          # Ensure Ruby version & RVM (like app_creator.rb)
          Stable::Services::Ruby.ensure_version(new_version)
          Stable::Services::Ruby.ensure_rvm!

          # Create gemset (like app_creator.rb)
          Stable::System::Shell.run("bash -lc 'source #{Stable::Services::Ruby.rvm_script} && rvm #{new_version} do rvm gemset create #{@name} || true'")

          rvm_cmd = Stable::Services::Ruby.rvm_prefix(new_version, @name)

          # Install Bundler (like app_creator.rb)
          Stable::System::Shell.run("bash -lc '#{rvm_cmd} gem install bundler --no-document'")

          # Run bundle install (like app_creator.rb)
          Stable::System::Shell.run(rvm_run('bundle install --jobs=4 --retry=3', chdir: app[:path]))
        end

        # Update app configuration (like app_creator.rb)
        unless ENV['STABLE_TEST_MODE']
          Dir.chdir(app[:path]) do
            File.write('.ruby-version', "#{new_version}\n")
            File.write('.ruby-gemset', "#{@name}\n")
          end
        end

        # Update registry
        Services::AppRegistry.update(@name, ruby: new_version)
        puts "   ✅ New Ruby #{new_version} environment set up with gems"
      end

      def rvm_run(cmd, chdir: nil)
        cd = chdir ? "cd #{chdir} && " : ''
        "bash -lc '#{cd}source #{Dir.home}/.rvm/scripts/rvm && rvm #{@version}@#{@name} do #{cmd}'"
      end

      def action(current_version, new_version)
        current_parts = current_version.split('.').map(&:to_i)
        new_parts = new_version.split('.').map(&:to_i)

        if new_parts[0] > current_parts[0] ||
           (new_parts[0] == current_parts[0] && new_parts[1] > current_parts[1]) ||
           (new_parts[0] == current_parts[0] && new_parts[1] == current_parts[1] && new_parts[2] > current_parts[2])
          'Upgrading'
        elsif new_parts[0] < current_parts[0] ||
              (new_parts[0] == current_parts[0] && new_parts[1] < current_parts[1]) ||
              (new_parts[0] == current_parts[0] && new_parts[1] == current_parts[1] && new_parts[2] < current_parts[2])
          'Downgrading'
        else
          'Switching'
        end
      end

      def past_tense_action(action)
        case action
        when 'Upgrading'
          'upgraded'
        when 'Downgrading'
          'downgraded'
        when 'Switching'
          'switched'
        else
          'updated'
        end
      end
    end
  end
end
