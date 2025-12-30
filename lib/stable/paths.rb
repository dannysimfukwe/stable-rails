module Stable
  module Paths
    def self.root
      File.expand_path("~/StableCaddy")
    end

    def self.caddy_dir
      root
    end

    def self.caddyfile
      File.join(caddy_dir, "Caddyfile")
    end

    def self.certs_dir
      File.join(root, "certs")
    end

    def self.apps_file
      File.join(root, "apps.yml")
    end
  end
end
