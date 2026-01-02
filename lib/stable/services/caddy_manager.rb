# frozen_string_literal: true

module Stable
  module Services
    class CaddyManager
      class << self
        def caddyfile
          Stable::Paths.caddyfile
        end

        def remove(domain)
          return unless File.exist?(caddyfile)

          content = File.read(caddyfile)
          content = remove_domain_block(content, domain)

          atomic_write(caddyfile, content)
          system("caddy fmt --overwrite #{caddyfile}")

          reload_if_running
        end

        def add_app(name, skip_ssl: false)
          app = Services::AppRegistry.all.find { |a| a[:name] == name }
          return unless app

          domain = app[:domain]
          port   = app[:port]

          ensure_certs_dir! unless skip_ssl
          ensure_cert_for!(domain) unless skip_ssl

          FileUtils.touch(caddyfile)
          content = File.read(caddyfile)

          content = remove_domain_block(content, domain)
          content << build_block(domain, port, skip_ssl: skip_ssl)

          atomic_write(caddyfile, content)
          system("caddy fmt --overwrite #{caddyfile}")

          ensure_running!
        end

        def reload
          if system('which caddy > /dev/null')
            pid = Process.spawn("caddy reload --config #{caddyfile}")
            Process.detach(pid.to_i)
          else
            puts 'Caddy not found. Install Caddy first.'
          end
        end

        def ensure_running!
          if running?
            reload
          else
            system("caddy run --config #{caddyfile} --adapter caddyfile &")
            sleep 2
          end
        end

        def reload_if_running
          reload if running?
        end

        def running?
          require 'socket'
          TCPSocket.new('127.0.0.1', 2019).close
          true
        rescue Errno::ECONNREFUSED
          false
        end

        private

        def ensure_cert_for!(domain)
          cert_path = File.join(Stable::Paths.certs_dir, "#{domain}.pem")
          key_path  = File.join(Stable::Paths.certs_dir, "#{domain}-key.pem")

          return if valid_pem?(cert_path) && valid_pem?(key_path)

          raise 'mkcert not installed' unless system('which mkcert > /dev/null')

          System::Shell.run(
            "mkcert -cert-file #{cert_path} -key-file #{key_path} #{domain}"
          )

          wait_for_pem!(cert_path)
          wait_for_pem!(key_path)
        end

        def build_block(domain, port, skip_ssl: false)
          cert_path = File.join(Stable::Paths.certs_dir, "#{domain}.pem") unless skip_ssl
          key_path  = File.join(Stable::Paths.certs_dir, "#{domain}-key.pem") unless skip_ssl
          prefix = skip_ssl ? 'http' : 'https'
          certs = skip_ssl ? '' : "tls #{cert_path} #{key_path}"
          <<~CADDY

            #{prefix}://#{domain} {
                reverse_proxy 127.0.0.1:#{port}
                #{certs}
            }
          CADDY
        end

        def remove_domain_block(content, domain)
          regex = %r{
            (https?|http)://#{Regexp.escape(domain)}\s*\{
            .*?
            \}
          }mx

          content.gsub(regex, '')
        end

        def atomic_write(path, content)
          tmp = "#{path}.tmp"
          File.write(tmp, content)
          File.rename(tmp, path)
        end

        def valid_pem?(path)
          File.exist?(path) &&
            File.size?(path) &&
            File.read(path, 64).include?('BEGIN')
        end

        def wait_for_pem!(path, timeout: 3)
          start = Time.now

          until valid_pem?(path)
            raise "Invalid PEM file: #{path}" if Time.now - start > timeout

            sleep 0.1
          end
        end

        def ensure_certs_dir!
          certs_dir = Stable::Paths.certs_dir
          FileUtils.mkdir_p(certs_dir)

          begin
            FileUtils.chown_R(Etc.getlogin, nil, certs_dir)
          rescue StandardError
          end

          Dir.glob("#{certs_dir}/*.pem").each do |pem|
            mode = pem.end_with?('-key.pem') ? 0o600 : 0o644
            begin
              FileUtils.chmod(mode, pem)
            rescue StandardError
              nil
            end
          end
        end
      end
    end
  end
end
