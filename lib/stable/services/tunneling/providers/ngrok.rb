# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module Stable
  module Services
    module Tunneling
      module Providers
        # ngrok provider
        class Ngrok
          NGROK_API   = 'http://127.0.0.1:4040/api/tunnels'
          MAX_RETRIES = 10
          RETRY_DELAY = 0.5

          # Expose the app via ngrok on the app's local port
          # skip_ssl is kept for future use
          def expose(domain, port:, skip_ssl: false)
            return stub_url(domain) if ENV['STABLE_TEST_MODE']

            if (tunnel = existing_tunnel)
              validate_tunnel!(tunnel, port)
              return tunnel['public_url']
            end

            start_ngrok(port)
            wait_for_url || abort('Failed to obtain ngrok URL')
          end

          private

          def existing_tunnel
            resp = JSON.parse(Net::HTTP.get(URI(NGROK_API)))
            resp['tunnels']&.find { |t| t['proto'] == 'https' }
          rescue StandardError
            nil
          end

          def validate_tunnel!(tunnel, port)
            target = tunnel.dig('config', 'addr')
            return if target == "http://localhost:#{port}"

            abort <<~MSG
              An ngrok tunnel is already running:

                #{tunnel['public_url']} → #{target}

              Free ngrok allows only one tunnel at a time.
              Stop it first:
                pkill ngrok
            MSG
          end

          def start_ngrok(port)
            @ngrok_pid = spawn(
              'ngrok', 'http', port.to_s, '--log=stdout',
              out: '/dev/null', err: '/dev/null'
            )
            Process.detach(@ngrok_pid)
          end

          def wait_for_url
            MAX_RETRIES.times do
              if (tunnel = existing_tunnel)
                return tunnel['public_url']
              end

              sleep RETRY_DELAY
            end
            nil
          end

          def stub_url(domain)
            "https://#{domain}-stable-share.test"
          end
        end
      end
    end
  end
end
