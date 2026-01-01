# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'stable-cli-rails'
  spec.version       = '0.6.9'
  spec.authors       = ['Danny Simfukwe']
  spec.email         = ['dannysimfukwe@gmail.com']

  spec.summary       = 'CLI tool to manage local Rails apps with automatic Caddy and HTTPS setup'
  spec.description   = 'Stable CLI: manage local Rails apps with automatic Caddy, HTTPS, and simple start/stop commands.'
  spec.homepage      = 'https://github.com/dannysimfukwe/stable-rails'
  spec.license       = 'MIT'

  spec.files         = Dir.glob('lib/**/*')
  spec.executables   = ['stable']
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.2.4'

  spec.add_dependency 'fileutils'
  spec.add_dependency 'thor'
end
