# frozen_string_literal: true

module Stable
  module Commands
    # Open App's work director
    class Workdir
      EDITOR_COMMANDS = {
        'vscode' => 'code',
        'sublime' => 'subl',
        'atom' => 'atom'
      }.freeze

      def initialize(app_name, editor)
        @app_name = app_name
        @editor   = editor.downcase
      end

      def call
        app = Services::AppRegistry.find(@app_name)
        abort "App '#{@app_name}' not found" unless app
        abort "App path does not exist: #{app[:path]}" unless Dir.exist?(app[:path])

        editor_cmd = EDITOR_COMMANDS[@editor] || @editor # support custom editors
        unless system("which #{editor_cmd} > /dev/null 2>&1")
          abort "Editor command not found: #{editor_cmd}"
        end

        puts "🚀 Opening #{@app_name} in #{@editor}..."
        system("#{editor_cmd} #{app[:path]}")
      end
    end
  end
end
