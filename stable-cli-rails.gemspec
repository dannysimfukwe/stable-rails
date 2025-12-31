Gem::Specification.new do |spec|
  spec.name          = "stable-cli-rails"
  spec.version       = "0.2.0"
  spec.authors       = ["Danny Simfukwe"]
  spec.email         = ["dannysimfukwe@gmail.com"]

  spec.summary       = "CLI tool to manage local Rails apps with automatic Caddy and HTTPS setup"
  spec.description   = File.read(File.expand_path("../README.md", __FILE__))
  spec.homepage      = "https://github.com/dannysimfukwe/stable-rails"
  spec.license       = "MIT"

  spec.files         = Dir.glob("lib/**/*") + ["README.md"]
  spec.executables   = ["stable"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor"
  spec.add_dependency "fileutils"
end
