# frozen_string_literal: true

module Stable
  module Services
    module Tunneling
      # Tunneling manager
      class Manager
        def initialize(provider:)
          @provider = provider.to_sym
        end

        # Expose the app domain using the correct port
        def expose_domain(domain, port:, skip_ssl: false)
          adapter.expose(domain, port: port, skip_ssl: skip_ssl)
        end

        private

        def adapter
          case @provider
          when :ngrok
            Providers::Ngrok.new
          when :stable
            Providers::Stable.new
          else
            abort "Unknown tunnel provider: #{@provider}"
          end
        end
      end
    end
  end
end
