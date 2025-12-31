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

      disable_rvm_autolibs!
    end

    def self.disable_rvm_autolibs!
      return unless system("which rvm > /dev/null")

      # Only run once
      marker = File.join(Paths.root, ".rvm_autolibs_disabled")
      return if File.exist?(marker)

      puts "Configuring RVM (disabling autolibs)..."

      system("bash -lc 'rvm autolibs disable'")
      system("bash -lc 'echo rvm_silence_path_mismatch_check_flag=1 >> ~/.rvmrc'")

      FileUtils.touch(marker)
    end
  end
end
