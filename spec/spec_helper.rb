require "erb"
require "rspec"
require "webmock/rspec"
require "simplecov"
require "fog/json"
SimpleCov.start

RSpec.configure do |config|

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

end

WebMock.disable_net_connect!(allow_localhost: true)

def create_response(request)
  request_body = Fog::JSON.decode(request.body)
  template = ERB.new File.read(File.join(File.dirname(__FILE__), "mocks", "create.txt"))
  template.result(binding)
end

def create_bad_response
  File.read(File.join(File.dirname(__FILE__), "mocks", "create_bad.txt"))
end

def create_ratelimit_response
  File.read(File.join(File.dirname(__FILE__), "mocks", "create_ratelimit.txt"))
end

def create_timeout_response
  File.read(File.join(File.dirname(__FILE__), "mocks", "create_timeout.txt"))
end

def delete_response
  File.read(File.join(File.dirname(__FILE__), "mocks", "delete.txt"))
end

def list_response
  File.read(File.join(File.dirname(__FILE__), "mocks", "list.txt"))
end

def view_response(label, region, image, type)
  template = ERB.new File.read(File.join(File.dirname(__FILE__), "mocks", "view.txt"))
  template.result(binding)
end
