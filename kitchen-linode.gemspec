# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "kitchen/driver/linode_version"

Gem::Specification.new do |s|
  s.name        = "kitchen-linode"
  s.version     = Kitchen::Driver::LINODE_VERSION
  s.authors     = ['Brett Taylor']
  s.email       = ['btaylor@linode.com']
  s.homepage    = 'https://github.com/ssplatt/kitchen-linode'
  s.summary     = "Linode Support for Test Kitchen"
  s.description = s.summary
  s.extra_rdoc_files = ['README.md', 'LICENSE']
  s.license       = 'Apache 2.0'

  s.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  s.executables    = []
  s.test_files    = s.files.grep(/^(test|spec|features)/)
  s.require_paths = ['lib']

  s.add_runtime_dependency "fog",  "~> 1.0"

  s.add_development_dependency "rspec",   "~> 3.0"
  s.add_development_dependency "rubocop",    "~> 0.24"
  s.add_development_dependency 'bundler', '~> 1.0'
end
