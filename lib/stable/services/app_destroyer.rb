# frozen_string_literal: true

module Stable
  module Services
    # Service for destroying a Rails application
    class AppDestroyer
      def initialize(name)
        @name = name
      end

      def call
        app = AppRegistry.find(@name)
        abort 'App not found' unless app

        display_warning(app)
        return unless confirm_destruction?

        puts "\n🗑️  Destroying #{@name}..."
        perform_destruction(app)
        puts "✅ Successfully destroyed #{@name}"
      end

      private

      def display_warning(app)
        puts "⚠️  WARNING: This will permanently delete the application '#{@name}'"
        puts "   Path: #{app[:path]}"
        puts "   Domain: #{app[:domain]}"
        puts '   This action CANNOT be undone!'
        puts ''
      end

      def confirm_destruction?
        print "Type '#{@name}' to confirm destruction: "
        confirmation = $stdin.gets&.strip
        puts ''

        if confirmation == @name
          true
        else
          puts "❌ Destruction cancelled - confirmation didn't match"
          false
        end
      end

      def perform_destruction(app)
        # Stop the app if running
        ProcessManager.stop(app)

        # Remove from infrastructure
        HostsManager.remove(app[:domain])
        CaddyManager.remove(app[:domain])
        AppRegistry.remove(@name)

        # Clean up RVM gemset
        cleanup_rvm_gemset(app)

        # Delete the project directory
        delete_project_directory(app[:path])

        # Reload Caddy
        CaddyManager.reload
      end

      def cleanup_rvm_gemset(app)
        return if ENV['STABLE_TEST_MODE']
        return unless Utils::Platform.unix?

        ruby_version = app[:ruby]
        clean_ruby_version = ruby_version.to_s.sub(/^ruby-/, '')
        gemset_name = "#{clean_ruby_version}@#{@name}"

        puts "   Cleaning up RVM gemset #{gemset_name}..."
        begin
          system("bash -lc 'source ~/.rvm/scripts/rvm && rvm gemset delete #{gemset_name} --force' 2>/dev/null || true")
          puts "   ✅ RVM gemset #{gemset_name} cleaned up"
        rescue StandardError => e
          puts "   ⚠️  Could not clean up RVM gemset #{gemset_name}: #{e.message}"
        end
      end

      def delete_project_directory(path)
        if ENV['STABLE_TEST_MODE']
          puts '   Deleting project directory...'
          return
        end

        if File.exist?(path)
          puts '   Deleting project directory...'
          FileUtils.rm_rf(path)
        else
          puts '   Project directory not found (already deleted?)'
        end
      end
    end
  end
end
