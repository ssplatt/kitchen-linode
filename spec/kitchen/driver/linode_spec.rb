require_relative "../../spec_helper"
require_relative "../../../lib/kitchen/driver/linode"

require "logger"
require "stringio"
require "rspec"
require "kitchen"
require "kitchen/driver/linode"
require "kitchen/provisioner/dummy"
require "kitchen/transport/dummy"
require "kitchen/verifier/dummy"
require "fog/linode"

describe Kitchen::Driver::Linode do
  let(:logged_output) { StringIO.new }
  let(:logger) { Logger.new(logged_output) }
  let(:config) { {} }
  let(:state) { {} }
  let(:rsa) { File.expand_path("~/.ssh/id_rsa") }
  let(:uuid_password) { "397a60bf-c7ac-4f5a-90c8-994fd835af8f" }
  let(:instance_name) { "kitchen-test" }
  let(:transport)     { Kitchen::Transport::Dummy.new }
  let(:platform)      { Kitchen::Platform.new(name: "linode/test") }
  let(:driver)        { Kitchen::Driver::Linode.new(config) }

  let(:instance) do
    double(
      name: instance_name,
      transport: transport,
      logger: logger,
      platform: platform,
      to_str: "instance"
    )
  end

  let(:driver) { described_class.new(config) }

  before(:each) do
    allow_any_instance_of(described_class).to receive(:instance)
      .and_return(instance)
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(rsa).and_return(true)
    allow(SecureRandom).to receive(:uuid).and_return(uuid_password)
    # skip sleeping so we're not waiting
    Retryable.configure do |config|
      config.sleep_method = lambda { |n| nil }
    end
    allow(driver).to receive(:sleep).and_return(nil)
  end

  describe "#finalize_config" do
    before(:each) { allow(File).to receive(:exist?).and_return(false) }

    context "private key, public key, and api token provided" do
      let(:config) do
        { private_key_path: "/tmp/key",
          public_key_path: "/tmp/key.pub",
          linode_token: "mytoken" }
      end

      it "raises no error" do
        expect(driver.finalize_config!(instance)).to be
      end
    end
  end

  describe "#initialize" do
    context "default options" do
      context "only a RSA SSH key available for the user" do
        before(:each) do
          allow(File).to receive(:exist?).and_return(false)
          allow(File).to receive(:exist?).with(rsa).and_return(true)
          allow(File).to receive(:exist?).with(rsa + ".pub").and_return(true)
        end

        it "uses the local user's RSA private key" do
          expect(driver[:private_key_path]).to eq(rsa)
        end

        it "uses the local user's RSA public key" do
          expect(driver[:public_key_path]).to eq(rsa + ".pub")
        end
      end

      it "defaults to no label" do
        expect(driver[:label]).to eq(nil)
      end

      it "defaults to a UUID as the password" do
        expect(driver[:password]).to eq(uuid_password)
      end

    end
    context "overridden options" do
      config = {
        linode_token: "mytesttoken",
        password: "somepassword",
        label: "thisserver",
        tags: %w{kitchen deleteme},
        hostname: "clevername",
        image: "linode/ubuntu20.04",
        region: "eu-central",
        type: "g6-standard-2",
        stackscript_id: 12345,
        stackscript_data: { test: "1234" },
        swap_size: 256,
        private_ip: true,
        authorized_users: ["timmy"],
        private_key_path: "/path/to/id_rsa",
        public_key_path: "/path/to/id_rsa.pub",
        disable_ssh_password: false,
        api_retries: 2,
      }

      let(:config) { config }

      config.each do |key, value|
        it "it uses the overridden #{key} option" do
          expect(driver[key]).to eq(value)
        end
      end
    end
  end

  describe "#create" do
    let(:linode_label) { "kitchen-test_500" }
    let(:driver) do
      d = super()
      allow(d).to receive(:setup_server).and_return(nil)
      d
    end

    context "when a server is already created" do
      it "does not create a new instance" do
        state[:linode_id] = "1"
        expect(driver).not_to receive(:create_server)
        driver.create(state)
      end
    end

    context "required options provided" do
      let(:driver) do
        d = super()
        allow(d).to receive(:setup_server).and_return(nil)
        allow(d).to receive(:suffixes).and_return((500..505))
        d
      end
      let(:config) {
        {
          linode_token: "somekey",
        }
      }

      it "returns nil, but modifies the state" do
        post_stub = stub_request(:post, "https://api.linode.com/v4/linode/instances")
          .to_return(lambda { |request| create_response(request) })
        list_stub = stub_request(:get, "https://api.linode.com/v4/linode/instances")
          .to_return(list_response)
        get_stub = stub_request(:get, "https://api.linode.com/v4/linode/instances/73577357")
          .to_return(view_response(linode_label, "us-east", "linode/test", "g6-nanode-1"))
        expect(driver.send(:create, state)).to eq(nil)
        expect(post_stub).to have_been_made.times(1)
        expect(list_stub).to have_been_made.times(1)
        expect(get_stub).to have_been_made.times(1)
        expect(state[:linode_id]).to eq(73577357)
        expect(state[:linode_label]).to eq("kitchen-job-kitchen-test_500")
      end

      it "handles rate limits and connection timeouts like a champ" do
        post_stub = stub_request(:post, "https://api.linode.com/v4/linode/instances")
          .to_return(
            create_timeout_response,
            create_timeout_response,
            create_ratelimit_response,
            create_ratelimit_response,
            lambda { |request| create_response(request) }
          )
        list_stub = stub_request(:get, "https://api.linode.com/v4/linode/instances")
          .to_return(list_response)
        get_stub = stub_request(:get, "https://api.linode.com/v4/linode/instances/73577357")
          .to_return(view_response(linode_label, "us-east", "linode/test", "g6-nanode-1"))
        driver.send(:create, state)
        expect(post_stub).to have_been_made.times(5)
        expect(list_stub).to have_been_made.times(1)
        expect(get_stub).to have_been_made.times(1)
        expect(state[:linode_id]).to eq(73577357)
        expect(state[:linode_label]).to eq("kitchen-job-kitchen-test_500")
      end

      it "raises an error if we run out of retries" do
        allow(driver).to receive(:sleep).and_return(nil) # skip sleeping so we're not waiting
        post_stub = stub_request(:post, "https://api.linode.com/v4/linode/instances")
          .to_return(
            create_timeout_response,
            create_timeout_response,
            create_timeout_response,
            create_timeout_response,
            create_timeout_response
          )
        list_stub = stub_request(:get, "https://api.linode.com/v4/linode/instances")
          .to_return(list_response)
        expect { driver.send(:create, state) }.to raise_error(Kitchen::ActionFailed)
        expect(list_stub).to have_been_made.times(1)
        expect(post_stub).to have_been_made.times(5)
      end

      it "raises an error if the api says we provided garbage data" do
        allow(driver).to receive(:sleep).and_return(nil) # skip sleeping so we're not waiting
        post_stub = stub_request(:post, "https://api.linode.com/v4/linode/instances")
          .to_return(create_bad_response)
        list_stub = stub_request(:get, "https://api.linode.com/v4/linode/instances")
          .to_return(list_response)
        expect { driver.send(:create, state) }.to raise_error(Kitchen::UserError)
        expect(list_stub).to have_been_made.times(1)
        expect(post_stub).to have_been_made.times(1)
      end

      it "it picks a different suffix when other servers exist" do
        post_stub = stub_request(:post, "https://api.linode.com/v4/linode/instances")
          .to_return(lambda { |request| create_response(request) })
        list_stub = stub_request(:get, "https://api.linode.com/v4/linode/instances")
          .to_return(
            body: '{"data": [{"label": "kitchen-job-kitchen-test_500"}, {"label": "kitchen-job-kitchen-test_501"}], "page": 1, "pages": 1, "results": 2}',
            headers: { "Content-Type" => "application/json" }
          )
        get_stub = stub_request(:get, "https://api.linode.com/v4/linode/instances/73577357")
          .to_return(view_response("kitchen-job-kitchen-test_502", "us-east", "linode/test", "g6-nanode-1"))
        driver.send(:create, state)
        expect(post_stub).to have_been_made.times(1)
        expect(list_stub).to have_been_made.times(1)
        expect(get_stub).to have_been_made.times(1)
        expect(state[:linode_label]).to eq("kitchen-job-kitchen-test_502")
      end

      it "throws an Action error when trying to create_server" do
        allow(driver).to receive(:create_server).and_raise(Fog::Errors::Error)
        expect { driver.send(:create, state) }.to raise_error(Kitchen::ActionFailed)
      end
    end

    context "when all the label suffixes are taken" do
      let(:compute) {
        double(
          servers: double(
            all: double(
              find: true
            )
          )
        )
      }
      before(:each) do
        {
          compute: compute,
        }.each do |k, v|
          allow_any_instance_of(described_class).to receive(k).and_return(v)
        end
      end

      it "throws a UserError" do
        expect { driver.send(:create, state) }.to raise_error(Kitchen::UserError)
      end
    end

  end

  describe "#destroy" do
    let(:linode_id) { "73577357" }
    let(:linode_label) { "kitchen-test_500" }
    let(:hostname) { "203.0.113.243" }
    let(:state) {
      {
        linode_id: linode_id,
        linode_label: linode_label,
        hostname: hostname,
      }
    }
    let(:config) {
      {
        linode_token: "somekey",
      }
    }
    let(:driver) { described_class.new(config) }

    context "when a server hasn't been created" do
      it "does not destroy anything" do
        state = {}
        expect(driver).not_to receive(:compute)
        expect(state).not_to receive(:delete)
        driver.destroy(state)
        expect(a_request(:get, "https://api.linode.com/v4/linode/instances/73577357"))
          .not_to have_been_made
        expect(a_request(:delete, "https://api.linode.com/v4/linode/instances/73577357"))
          .not_to have_been_made
      end
    end

    context "when a server doesn't exist" do
      it "doesn't get nervous about the 404" do
        get_stub = stub_request(:get, "https://api.linode.com/v4/linode/instances/73577357")
          .to_return(status: [404, "Not Found"])
        expect(state).to receive(:delete).with(:linode_id)
        expect(state).to receive(:delete).with(:linode_label)
        expect(state).to receive(:delete).with(:hostname)
        expect(state).to receive(:delete).with(:ssh_key)
        expect(state).to receive(:delete).with(:password)
        driver.destroy(state)
        expect(get_stub).to have_been_made.times(1)
        expect(a_request(:delete, "https://api.linode.com/v4/linode/instances/73577357"))
          .not_to have_been_made
      end
    end

    context "when a server exists" do
      it "properly nukes it" do
        get_stub = stub_request(:get, "https://api.linode.com/v4/linode/instances/73577357")
          .to_return(view_response(linode_label, "us-test", "linode/test", "testnode"))
        delete_stub = stub_request(:delete, "https://api.linode.com/v4/linode/instances/73577357")
          .to_return(delete_response)
        expect(state).to receive(:delete).with(:linode_id)
        expect(state).to receive(:delete).with(:linode_label)
        expect(state).to receive(:delete).with(:hostname)
        expect(state).to receive(:delete).with(:ssh_key)
        expect(state).to receive(:delete).with(:password)
        driver.destroy(state)
        expect(get_stub).to have_been_made.times(1)
        expect(delete_stub).to have_been_made.times(1)
      end
    end

  end

end
