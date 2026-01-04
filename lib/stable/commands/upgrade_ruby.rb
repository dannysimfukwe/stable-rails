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

        # Clean approach: Clear old gemset and recreate fresh one with gems (like creating a new app)
        if platform == :windows
          puts "Setting up Ruby #{@version} environment..."
          puts "Installing gems with Ruby #{@version}..."

          # On Windows, just update the ruby-version and run bundle install
          # Remove old Gemfile.lock for fresh resolution
          gemfile_lock = File.join(app[:path], 'Gemfile.lock')
          FileUtils.rm_f(gemfile_lock)

          puts 'Run the following commands manually in the app directory:'
          puts "  cd #{app[:path]}"
          puts '  bundle install'
          puts ''
          puts 'This will install gems with the correct Ruby version.'
          success = true
        else
          puts "Setting up fresh gemset for Ruby #{@version}..."

        # 1. Clear/uninstall the current gemset (3.4.4@myapp)
        puts 'Clearing old gemset...'
        unless ENV['STABLE_TEST_MODE']
          Stable::System::Shell.run("bash -lc 'source #{Stable::Services::Ruby.rvm_script} && rvm gemset delete #{@name} --force || true'")
        end

        # 2. Recreate the gemset and install gems in one clean operation
        puts "Setting up fresh gemset #{@version}@#{@name}..."
        unless ENV['STABLE_TEST_MODE']
          # Verify app directory and Gemfile exist
          unless File.directory?(app[:path])
            puts "❌ App directory not found: #{app[:path]}"
            return
          end

          gemfile_path = File.join(app[:path], 'Gemfile')
          unless File.exist?(gemfile_path)
            puts "❌ Gemfile not found in: #{app[:path]}"
            return
          end

          # Remove old Gemfile.lock for fresh resolution
          gemfile_lock = File.join(app[:path], 'Gemfile.lock')
          FileUtils.rm_f(gemfile_lock)

          # Create gemset and run bundle install in a single RVM context to avoid native extension issues
          # Use BUNDLE_GEMFILE to specify the Gemfile location explicitly
          gemfile_path = File.join(app[:path], 'Gemfile')
          bundle_cmd = "BUNDLE_GEMFILE=#{Shellwords.escape(gemfile_path)} bundle install --redownload --no-cache"
          full_cmd = "bash -lc 'source #{Stable::Services::Ruby.rvm_script} && rvm #{@version} do rvm gemset create #{@name} && rvm #{@version}@#{@name} do cd #{Shellwords.escape(app[:path])} && #{bundle_cmd}'"
          success = Stable::System::Shell.run(full_cmd)
        else
          success = true
        end
        end

        if success
          if platform == :windows
            puts "✅ Ruby version updated to #{@version}!"
            puts "   Run 'bundle install' manually in the app directory to install gems."
          else
            puts "✅ Gems installed successfully in Ruby #{@version}!"
          end
        else
          puts '⚠️  Gem installation had issues, but environment is set up.'
        end

        # Update configuration
        puts 'Updating app configuration...'
        File.write(File.join(app[:path], '.ruby-version'), @version)
        File.write(File.join(app[:path], '.ruby-gemset'), "#{@name}\n") unless platform == :windows
        Services::AppRegistry.update(@name, ruby: @version)

        puts ''
        puts "✅ #{@name} #{action(current_version, @version).split.first.downcase}d to Ruby #{@version}!"
        if platform == :windows
          puts '   Ruby version updated - run bundle install manually'
        else
          puts "   Old gemset cleared, fresh #{@version}@#{@name} gemset created with gems"
        end
        puts ''
        puts "Start with: stable start #{@name}"
      end

      private

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
    end
  end
end
