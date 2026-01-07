# frozen_string_literal: true

module Stable
  module Services
    module Rails
      # Authorize ngro host
      class HostAuthorization
        MARKER_BEGIN = '# BEGIN Stable ngrok hosts'
        MARKER_END   = '# END Stable ngrok hosts'

        def self.allow_ngrok!(app_path)
          env_file = File.join(app_path, 'config/environments/development.rb')
          return unless File.exist?(env_file)

          content = File.read(env_file)
          return if content.include?(MARKER_BEGIN)

          # Only needed for Rails 6+
          return unless rails_host_authorization_enabled?(app_path)

          injection = <<~RUBY

            #{MARKER_BEGIN}
            config.hosts << ".ngrok-free.app"
            config.hosts << ".ngrok.app"
            #{MARKER_END}
          RUBY

          updated = content.sub(
            /Rails\.application\.configure do\s*\n/,
            "\\0#{injection}"
          )

          File.write(env_file, updated)
        end

        def self.remove_ngrok!(app_path)
          env_file = File.join(app_path, 'config/environments/development.rb')
          return unless File.exist?(env_file)

          content = File.read(env_file)
          return unless content.include?(MARKER_BEGIN)

          cleaned = content.sub(
            /\n\s*#{Regexp.escape(MARKER_BEGIN)}.*?#{Regexp.escape(MARKER_END)}\n/m,
            "\n"
          )

          File.write(env_file, cleaned)
        end

        def self.rails_host_authorization_enabled?(app_path)
          env_rb = File.join(app_path, 'config/application.rb')
          return false unless File.exist?(env_rb)

          content = File.read(env_rb)
          content.include?('config.load_defaults 6') ||
            content.include?('config.load_defaults 7') ||
            content.include?('config.load_defaults 8')
        end
      end
    end
  end
end
