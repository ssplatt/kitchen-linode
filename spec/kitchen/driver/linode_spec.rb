# Encoding: UTF-8

require_relative '../../spec_helper'
require_relative '../../../lib/kitchen/driver/linode'

require 'logger'
require 'stringio'
require 'rspec'
require 'kitchen'
require 'kitchen/driver/linode'
require 'kitchen/provisioner/dummy'
require 'kitchen/transport/dummy'
require 'kitchen/verifier/dummy'
require 'fog'

describe Kitchen::Driver::Linode do
  let(:logged_output) { StringIO.new }
  let(:logger) { Logger.new(logged_output) }
  let(:config) { Hash.new }
  let(:state) { Hash.new }
  let(:rsa) { File.expand_path('~/.ssh/id_rsa') }
  let(:instance_name) { 'the_thing' }
  let(:transport)     { Kitchen::Transport::Dummy.new }
  let(:platform)      { Kitchen::Platform.new(name: 'fake_platform') }
  let(:driver)        { Kitchen::Driver::Openstack.new(config) }

  let(:instance) do
    double(
      name: instance_name,
      transport: transport,
      logger: logger,
      platform: platform,
      to_str: 'instance'
    )
  end

  let(:driver) { described_class.new(config) }

  before(:each) do
    allow_any_instance_of(described_class).to receive(:instance)
      .and_return(instance)
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(rsa).and_return(true)
  end

  describe '#initialize' do
    context 'overridden options' do
      let(:config) do
        {
          image: 139,
          data_center: 10,
          flavor: 2,
          kernel: 215,
          username: 'someuser',
          server_name: 'thisserver',
          private_key_path: '/path/to/id_rsa',
        }
      end

      it 'uses all the overridden options' do
        drv = driver
        config.each do |k, v|
          expect(drv[k]).to eq(v)
        end
      end

      it 'overrides server name prefix with explicit server name, if given' do
        expect(driver[:server_name]).to eq(config[:server_name])
      end
    end
  end

end