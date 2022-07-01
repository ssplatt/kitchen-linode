lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "kitchen/driver/linode_version"

Gem::Specification.new do |spec|
  spec.name          = "kitchen-linode"
  spec.version       = Kitchen::Driver::LINODE_VERSION
  spec.authors       = ["Brett Taylor"]
  spec.email         = ["btaylor@linode.com"]
  spec.description   = "A Test Kitchen Driver for Linode"
  spec.summary       = "A Test Kitchen Driver to use Linodes as your development environment"
  spec.homepage      = "https://github.com/ssplatt/kitchen-linode"
  spec.license       = "Apache-2.0"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = []
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 2.6"

  spec.add_dependency "fog-linode", "~> 0.0.1.rc2"
  spec.add_dependency "retryable", ">= 2.0", "< 4.0"
  spec.add_dependency "test-kitchen", ">= 1.4", "< 4"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "chefstyle", "= 2.2.2"
  spec.add_development_dependency "countloc", "~> 0.4"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.8"
  spec.add_development_dependency "simplecov", "~> 0.9"
  spec.add_development_dependency "webmock", "~> 3.5"
end
