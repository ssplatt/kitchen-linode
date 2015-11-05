# -*- encoding: utf-8 -*-
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

require 'benchmark'
require 'fog'
require 'kitchen'
require 'etc'
require 'socket'
require 'json'

module Kitchen
  module Driver
    # Linode driver for Kitchen.

    class Linode < Kitchen::Driver::SSHBase
      default_config :username, 'root'
      default_config :password, nil
      default_config(:image) { |driver| driver.default_image }
      default_config :data_center, 1
      default_config :flavor, 1
      default_config :payment_terms, 1
      default_config :ssh_key_name, nil
      default_config :kernel, 215

      default_config :api_key do
        ENV['LINODE_API_KEY']
      end

      required_config :api_key
      
      default_config :private_key_path do
        %w(id_rsa id_dsa).map do |k|
          f = File.expand_path("~/.ssh/#{k}")
          f if File.exist?(f)
        end.compact.first
      end
      default_config :public_key_path do |driver|
        driver[:private_key_path] + '.pub' if driver[:private_key_path]
      end
      
      required_config :private_key_path
      required_config :public_key_path do |_, value, driver|
        if value.nil? && driver[:key_name].nil?
          fail(UserError,
               'Either a `:public_key_path` or `:key_name` is required')
        end
      end
      
      # Set the proper server name in the config
      def config_server_name
        return if config[:server_name]

        if config[:server_name_prefix]
          config[:server_name] = server_name_prefix(
            config[:server_name_prefix]
          )
        else
          config[:server_name] = default_name
        end
      end
      
      @client = Fog::Compute.new(:provider => 'Linode', :linode_api_key => config[:api_key])

      def create(state)
        # create and boot server
        
        config_server_name
        
        if state[:server_id]
          info "#{config[:server_name]} (#{state[:server_id]}) already exists."
          return
        end

        if config[:password]
          root_pass = config[:password]
        else
          root_pass = Digest::SHA2.new.update(config[:api_key]).to_s
        end
        
        # set datacenter
        data_center = @client.data_centers.get(config[:data_center])
        if data_center.nil?
          data_center = @client.data_centers.find { |dc| dc.location == config[:data_center] }
        end
        if data_center.nil?
          data_center = @client.data_centers.find { |dc| dc.location =~ /#{config[:data_center]}/ }
        end
        
        # set flavor
        flavor = @client.flavors.get(config[:flavor])
        if flavor.nil?
          flavor = @client.flavors.find { |f| f.ram == config[:flavor] }
        end
        if flavor.nil?
          flavor = @client.flavors.find { |f| f.name == config[:flavor] }
        end
        if flavor.nil?
          flavor = @client.flavors.find { |f| f.name =~ /#{config[:flavor]}/ }
        end
        
        # set image
        image = @client.images.get(config[:image])
        if image.nil?
          image = @client.images.find { |i| i.name == config[:image] }
        end
        if image.nil?
          image = @client.images.find { |i| i.name == /#{config[:image]}/ }
        end
        
        # set kernel
        kernel = @client.kernels.get(config[:kernel])
        
        if kernel.nil?
          kernel = @client.kernels.find { |k| k.name == config[:kernel] }
        end
        if kernel.nil?
          kernel = @client.kernels.find { |k| k.name == /#{config[:kernel]}/ }
        end

        info("Creating Linode.")

        # submit new linode request
        server = @client.servers.create(
          :data_center => data_center,
          :flavor => flavor, 
          :payment_terms => 1, 
          :name => config[:server_name],
          :image => image,
          :kernel => kernel,
          :password => root_pass
        )

        # assign the machine id for reference in other commands
        state[:server_id] = server.id
        state[:hostname] = config[:server_name]
        
        info("Linode <#{state[:server_id]}> created.")

        linode ||= @client.servers.find { |s| s.id == state[:server_id] }

        wait_for_sshd(state[:hostname]); print "(ssh ready)\n"
        debug("linode:create #{state[:hostname]}")
      end

      def destroy(state)
        return if state[:server_id].nil?
        server = @client.servers.get(state[:server_id])

        server.destroy

        info("Linode <#{state[:server_id]}> destroyed.")
        state.delete(:linode_id)
        state.delete(:hostname)
      end
      
      private
      
      def default_name
        "kitchen_linode-#{rand.to_s.split('.')[1]}"
      end
    end
  end
end

# vim: ai et ts=2 sts=2 sw=2 ft=ruby
