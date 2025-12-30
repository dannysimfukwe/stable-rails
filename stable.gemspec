Gem::Specification.new do |spec|
  spec.name          = "stable"
  spec.version       = "0.1.0"
  spec.authors       = ["Danny Simfukwe"]
  spec.summary       = "Zero-config local Rails development"

  spec.files         = Dir["lib/**/*", "bin/*"]
  spec.executables   = ["stable"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor"
  spec.add_development_dependency "rake"
end
