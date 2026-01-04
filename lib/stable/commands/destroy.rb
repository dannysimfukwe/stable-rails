# frozen_string_literal: true

require 'io/console'

module Stable
  module Commands
    # Destroy command - permanently deletes a Rails application with confirmation
    class Destroy
      def initialize(name)
        @name = name
      end

      def call
        app = Services::AppRegistry.find(@name)
        abort 'App not found' unless app

        display_warning(app)
        return unless confirm_destruction

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

      def confirm_destruction
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
        Services::ProcessManager.stop(app)

        # Remove from infrastructure
        Services::HostsManager.remove(app[:domain])
        Services::CaddyManager.remove(app[:domain])
        Services::AppRegistry.remove(@name)

        # Clean up RVM gemset
        cleanup_rvm_gemset(app)

        # Delete the project directory
        delete_project_directory(app[:path])

        # Reload Caddy
        Services::CaddyManager.reload
      end

      def cleanup_rvm_gemset(app)
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

      def delete_project_directory(path)
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
