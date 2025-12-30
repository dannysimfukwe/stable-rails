require "fileutils"

module Stable
  module Bootstrap
    def self.run!
      FileUtils.mkdir_p(Paths.root)
      FileUtils.mkdir_p(Paths.caddy_dir)
      FileUtils.mkdir_p(Paths.certs_dir)

      unless File.exist?(Paths.apps_file)
        File.write(Paths.apps_file, "--- []\n")
      end

      unless File.exist?(Paths.caddyfile)
        File.write(Paths.caddyfile, "")
      end
    end
  end
end
