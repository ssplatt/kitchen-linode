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
  let(:instance_name) { "the_thing" }
  let(:transport)     { Kitchen::Transport::Dummy.new }
  let(:platform)      { Kitchen::Platform.new(name: "fake_platform") }
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
      let(:config) do
        {
          image: "linode/ubuntu20.04",
          region: "eu-central",
          type: "g6-standard-2",
          kernel: "linode/grub2",
          username: "someuser",
          label: "thisserver",
          private_key_path: "/path/to/id_rsa",
          public_key_path: "/path/to/id_rsa.pub",
          password: "somepassword",
          api_retries: 2,
        }
      end

      it "uses all the overridden options" do
        drv = driver
        config.each do |k, v|
          expect(drv[k]).to eq(v)
        end
      end

      it "overrides server name prefix with explicit server name, if given" do
        expect(driver[:label]).to eq(config[:label])
      end
    end
  end

  describe "#create" do
    let(:server) do
      double(id: "test123", wait_for: true, public_ip_address: %w{1.2.3.4})
    end
    let(:driver) do
      d = super()
      allow(d).to receive(:create_server).and_return(server)
      allow(d).to receive(:setup_server).and_return(true)
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
      let(:config) do
        {
          username: "someuser",
          linode_token: "somekey",
          disable_ssl_validation: false,
        }
      end
      let(:server) do
        double(id: 123456, wait_for: true, ipv4: %w{1.2.3.4}, label: "test123")
      end

      let(:driver) do
        d = described_class.new(config)
        allow(d).to receive(:create_server).and_return(server)
        allow(server).to receive(:id).and_return(123456)

        allow(server).to receive(:wait_for)
          .with(an_instance_of(Integer)).and_yield
        allow(d).to receive(:bourne_shell?).and_return(false)
        d
      end

      it "returns nil, but modifies the state" do
        expect(driver.send(:create, state)).to eq(nil)
        expect(state[:linode_id]).to eq(123456)
        expect(state[:linode_label]).to eq("test123")
      end

      it "throws an Action error when trying to create_server" do
        allow(driver).to receive(:create_server).and_raise(Fog::Errors::Error)
        expect { driver.send(:create, state) }.to raise_error(Kitchen::ActionFailed)
      end
    end
  end

end
