# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kitchen/driver/linode_version'

Gem::Specification.new do |spec|
  spec.name          = 'kitchen-linode'
  spec.version       = Kitchen::Driver::LINODE_VERSION
  spec.authors       = ['Brett Taylor']
  spec.email         = ['btaylor@linode.com']
  spec.description   = 'A Test Kitchen Driver for Linode'
  spec.summary       = 'A Test Kitchen Driver to use Linodes as your development environment'
  spec.homepage      = 'https://github.com/ssplatt/kitchen-linode'
  spec.license       = 'Apache-2.0'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = []
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'test-kitchen', '~> 1.4'
  spec.add_dependency 'fog', '~> 1.34'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake', '~> 10.4'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'codeclimate-test-reporter'
end
