# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'stable-cli-rails'
  spec.version       = '0.8.0'
  spec.authors       = ['Danny Simfukwe']
  spec.email         = ['dannysimfukwe@gmail.com']

  spec.summary       = 'CLI tool to manage local Rails apps with automatic Caddy and HTTPS setup'
  spec.description   = 'Stable is a cross-platform CLI tool to manage local Rails applications ' \
                       'with automatic Caddy setup, local trusted HTTPS certificates, ' \
                       'and easy start/stop functionality. Supports macOS, Linux, and Windows.'
  spec.homepage      = 'https://github.com/dannysimfukwe/stable-rails'
  spec.license       = 'MIT'

  spec.files         = Dir.glob('lib/**/*')
  spec.executables   = ['stable']
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.2.4'

  spec.add_dependency 'thor', '~> 1.2.2'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
