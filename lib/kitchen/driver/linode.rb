# -*- encoding: utf-8 -*-
#
# Author:: Brett Taylor (<btaylor@linode.com>)
#
# Copyright (C) 2015, Brett Taylor
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'kitchen'
require 'fog'
require_relative 'linode_version'

module Kitchen

  module Driver
    # Linode driver for Kitchen.
    #
    # @author Brett Taylor <btaylor@linode.com>
    class Linode < Kitchen::Driver::Base
      kitchen_driver_api_version 2
      plugin_version Kitchen::Driver::LINODE_VERSION
      
      default_config :username, 'root'
      default_config :password, nil
      default_config :image, 140
      default_config :data_center, 4
      default_config :flavor, 1
      default_config :payment_terms, 1
      default_config :ssh_key_name, nil
      default_config :kernel, 138
      
      default_config :sudo, true
      default_config :port, 22
      default_config :ssh_timeout, 600
      
      default_config :private_key, nil
      default_config :private_key_path, "~/.ssh/id_rsa"
      default_config :public_key, nil
      default_config :public_key_path, "~/.ssh/id_rsa.pub"
      
      default_config :api_key, ENV['LINODE_API_KEY']
      
      required_config :api_key

      def create(state)
        # create and boot server
        config_server_name
        
        if state[:server_id]
          info "#{config[:server_name]} (#{state[:server_id]}) already exists."
          return
        end
        
        info("Creating Linode.")
        
        server = create_server
        
        # assign the machine id for reference in other commands
        state[:server_id] = server.id
        state[:hostname] = server.public_ip_address
        info("Linode <#{state[:server_id]}> created.")
        info("Waiting for linode to boot...")
        server.wait_for { ready? }
        info("Linode <#{state[:server_id]}, #{state[:hostname]}> ready.")
        setup_ssh(server, state) if bourne_shell?
      rescue Fog::Errors::Error, Excon::Errors::Error => ex
        raise ActionFailed, ex.message
      end

      def destroy(state)
        return if state[:server_id].nil?
        server = compute.servers.get(state[:server_id])

        server.destroy

        info("Linode <#{state[:server_id]}> destroyed.")
        state.delete(:server_id)
        state.delete(:hostname)
      end
      
      private
      
      def compute
        Fog::Compute.new(:provider => 'Linode', :linode_api_key => config[:api_key])
      end
      
      def create_server
        if config[:password].nil?
          config[:password] = [*('a'..'z'),*('A'..'Z'),*('0'..'9')].shuffle[0,20].join
        end
        
        # set datacenter
        if config[:data_center].is_a? Integer
          data_center = compute.data_centers.find { |dc| dc.id == config[:data_center] }
        else
          data_center = compute.data_centers.find { |dc| dc.location == config[:data_center] }
          if data_center.nil?
            data_center = compute.data_centers.find { |dc| dc.location =~ /#{config[:data_center]}/ }
          end
        end
        if data_center.nil?
          fail(UserError, "No match for data_center: #{config[:data_center]}")
        end
        info "Got data center: #{data_center.location}..."
        
        # set flavor
        if config[:flavor].is_a? Integer
          if config[:flavor] < 10
            flavor = compute.flavors.get(config[:flavor])
          else
            flavor = compute.flavors.find { |f| f.ram == config[:flavor] }
          end
        else
          flavor = compute.flavors.find { |f| f.name == config[:flavor] }
          if flavor.nil?
            flavor = compute.flavors.find { |f| f.name =~ /#{config[:flavor]}/ }
          end
        end
        if flavor.nil?
          fail(UserError, "No match for flavor: #{config[:flavor]}")
        end
        info "Got flavor: #{flavor.name}..."
        
        # set image/distribution
        if config[:image].is_a? Integer
          image = compute.images.get(config[:image])
        else
          image = compute.images.find { |i| i.name == config[:image] }
          if image.nil?
            image = compute.images.find { |i| i.name =~ /#{config[:image]}/ }
          end
        end
        if image.nil?
          fail(UserError, "No match for image: #{config[:image]}")
        end
        info "Got image: #{image.name}..."
        
        # set kernel
        if config[:kernel].is_a? Integer
          kernel = compute.kernels.get(config[:kernel])
        else
          kernel = compute.kernels.find { |k| k.name == config[:kernel] }
          if kernel.nil?
            kernel = compute.kernels.find { |k| k.name =~ /#{config[:kernel]}/ }
          end
        end
        if kernel.nil?
          fail(UserError, "No match for kernel: #{config[:kernel]}")
        end
        info "Got kernel: #{kernel.name}..."
        
        if config[:private_key_path]
          config[:private_key_path] = File.expand_path(config[:private_key_path])
        end
        if config[:public_key_path]
          config[:public_key_path] = File.expand_path(config[:public_key_path])
        end

        # submit new linode request
        compute.servers.create(
          :data_center => data_center,
          :flavor => flavor, 
          :payment_terms => config[:payment_terms], 
          :name => config[:server_name],
          :image => image,
          :kernel => kernel,
          :username => config[:username],
          :password => config[:password]
        )
      end
      
      def setup_ssh(server, state)
        state[:ssh_key] = config[:private_key_path]
        do_ssh_setup(state, config)
      end

      def do_ssh_setup(state, config)
        info "Setting up SSH access for key <#{config[:public_key_path]}>"
        info "Connecting <#{config[:username]}@#{state[:hostname]}>..."
        ssh = Fog::SSH.new(state[:hostname],
                           config[:username],
                           :password => config[:password],
                           :timeout => config[:ssh_timeout])
        pub_key = open(config[:public_key_path]).read
        @max_interval = 60
        @max_retries = 10
        @retries = 0
        begin
          ssh.run([
            %(mkdir .ssh),
            %(echo "#{pub_key}" >> ~/.ssh/authorized_keys),
            %(passwd -l #{config[:username]})
          ])
        rescue
          @retries ||= 0
          if @retries < @max_retries
            info "Retrying connection..."
            sleep [2**(@retries - 1), @max_interval].min
            @retries += 1
            retry
          else
            raise
          end
        end
        info "Done setting up SSH access."
      end
      
      # Set the proper server name in the config
      def config_server_name
        return if config[:server_name]
        config[:server_name] = "kitchen_linode-#{rand.to_s.split('.')[1]}"
      end
    end
  end
end
