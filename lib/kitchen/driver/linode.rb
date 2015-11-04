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
require 'linode'
require 'kitchen'
require 'etc'
require 'socket'
require 'json'

module Kitchen
  module Driver
    # Linode driver for Kitchen.

    class Linode < Kitchen::Driver::SSHBase
      default_config :username, 'root'
      default_config :api_url, ENV['LINODE_URL']
      default_config :distributionid, nil
      default_config(:distribution) { |driver| driver.default_image }
      default_config :imageid, nil
      default_config :image, nil 
      default_config :datacenterid
      default_config :datacenter, 'dallas'
      default_config :planid, nil
      default_config :plan, 'Linode 1024'
      default_config :paymentterm, '1'
      default_config :private_networking, false
      default_config :ca_path, nil
      default_config :ssh_key_name, nil
      default_config :setup, true
      default_config :xvda_size, true
      default_config :swap_size, '256'
      default_config :kernelid, nil
      default_config :kernel, 'Latest 64 bit'
      default_config :label, nil
      default_config :group, nil
      default_config(:server_name) { |driver| driver.default_name }

      default_config :api_key do
        ENV['LINODE_API_KEY']
      end

      default_config :ssh_key_ids do
        ENV['LINODE_SSH_KEY_IDS'] || ENV['SSH_KEY_IDS']
      end

      required_config :api_key
      required_config :ssh_key_ids
      
      @client = Linode::Linode.new(api_key: config[:api_key])

      def create(state)
        # create and boot server
        # 1. create linode
        # 2. create disk
        # 3. deploy image

        ssh_key_id = config[:ssh_key_ids][0] if config[:ssh_key_ids].is_a?(Array)
        if ssh_key_id
          pubkey = File.read(File.expand_path("#{ssh_key_id}.pub"))
        end

        if config[:root_pass]
          root_pass = config[:root_pass]
        else
          root_pass = Digest::SHA2.new.update(config[:api_key]).to_s
        end

        if config[:distribution]
          distributions = @client.avail.distributions
          distribution = distributions.find { |d| d.label.downcase.include? config[:distribution].downcase }
          fail(Errors::DistroMatch, distro: config[:distribution].to_s) if distribution.nil?
          distribution_id = distribution.distributionid || nil
        else
          distribution_id = config[:distributionid]
        end

        if config[:imageid]
          distribution_id = nil
          images = @client.image.list
          image = images.find { |i| i.imageid == config[:imageid] }
          fail Errors::ImageMatch, image: config[:imageid].to_s  if image.nil?
          image_id = image.imageid || nil
        elsif config[:image]
          distribution_id = nil
          images = @client.image.list
          image = images.find { |i| i.label.downcase.include? config[:image].downcase }
          fail Errors::ImageMatch, image: config[:image].to_s  if image.nil?
          image_id = image.imageid || nil
        end

        if config[:kernel]
          kernels = @client.avail.kernels
          kernel = kernels.find { |k| k.label.downcase.include? config[:kernel].downcase }
          raise( Errors::KernelMatch, kernel: config[:kernel].to_s ) if kernel == nil
          kernel_id = kernel.kernelid || nil
        else
          kernel_id = config[:kernelid]
        end

        if config[:datacenter]
          datacenters = @client.avail.datacenters
          datacenter = datacenters.find { |d| d.abbr == config[:datacenter] }
          fail Errors::DatacenterMatch, datacenter: config[:datacenter] if datacenter.nil?
          datacenter_id = datacenter.datacenterid
        else
          datacenters = @client.avail.datacenters
          datacenter = datacenters.find { |d| d.datacenterid == config[:datacenterid] }
          fail Errors::DatacenterMatch, datacenter: config[:datacenter] if datacenter.nil?
          datacenter_id = datacenter.datacenterid
        end

        if config[:plan]
          plans = @client.avail.linodeplans
          plan = plans.find { |p| p.label.include? config[:plan] }
          fail Errors::PlanID, plan: config[:plan] if plan.nil?
          plan_id = plan.planid
        else
          plans = @client.avail.linodeplans
          plan = plans.find { |p| p.planid == config[:planid] }
          fail Errors::PlanID, plan: config[:plan] if plan.nil?
          plan_id = config[:planid]
        end

        ### Disk Images
        xvda_size, swap_size, disk_sanity = config[:xvda_size], config[:swap_size], true

        # Sanity checks for disk size
        if xvda_size != true
          disk_sanity = false if ( xvda_size.to_i + swap_size.to_i) > ( plan['disk'].to_i * 1024)
        end

        # throw if disk sizes are too large
        if xvda_size == true
          xvda_size = ( ( plan['disk'].to_i * 1024) - swap_size.to_i)
        elsif disk_sanity == false
          fail Errors::DiskSize, current: (xvda_size.to_i + swap_size.to_i), max: ( plan['disk'].to_i * 1024)
        end

        info("Creating Linode.")

        # submit new linode request
        result = @client.linode.create(
          planid: plan_id,
          datacenterid: datacenter_id,
          paymentterm: config[:paymentterm] || 1
        )

        # assign the machine id for reference in other commands
        state[:server_id] = result['linodeid'].to_s
        
        info("Linode <#{state[:server_id]}> created.")

        if distribution_id
          swap = @client.linode.disk.create(
            linodeid: state[:server_id],
            label: 'TestKitchen swap',
            type: 'swap',
            size: swap_size
          )

          disk = @client.linode.disk.createfromdistribution(
            linodeid: state[:server_id],
            distributionid: distribution_id,
            label: 'TestKitchen Disk Distribution ' + distribution_id.to_s + ' Linode ' + result['linodeid'].to_s,
            type: 'ext4',
            size: xvda_size,
            rootsshkey: pubkey,
            rootpass: root_pass
          )
        elsif image_id
          disk = @client.linode.disk.createfromimage(
            linodeid: state[:server_id],
            imageid: image_id,
            label: 'TestKitchen Disk Image (' + image_id.to_s + ') for ' + result['linodeid'].to_s,
            size: xvda_size,
            rootsshkey: pubkey,
            rootpass: root_pass
          )

          swap = @client.linode.disk.create(
            linodeid: state[:server_id],
            label: 'TestKitchen swap',
            type: 'swap',
            size: swap_size
          )
        end

        linconfig = @client.linode.config.create(
          linodeid: state[:server_id],
          label: 'TestKitchen Config',
          disklist: "#{disk['diskid']},#{swap['diskid']}",
          kernelid: kernel_id
        )

        if config[:private_networking]
          private_network = @client.linode.ip.addprivate linodeid: state[:server_id]
        end

        label = config[:label]
        label = label || config[:server_name] if config[:server_name] != 'default'
        label = label || get_server_name
        
        state[:hostname] = label

        group = config[:group]
        group = "" if config[:group] == false

        result = @client.linode.update(
          linodeid: state[:server_id],
          label: label,
          lpm_displaygroup: group
        )

        info ("Booting Linode #{state[:server_id]}")

        bootjob = @client.linode.boot linodeid: state[:server_id]
        # sleep 1 until ! @client.linode.job.list(:linodeid => result['linodeid'], :jobid => bootjob['jobid'], :pendingonly => 1).length
        wait_for_event(env, bootjob['jobid'])

        info("Linode <#{state[:linode_id]}> created.")

        loop do
          sleep 8
          linode = @client.linode.list(linodeid: state[:linode_id])
          public_network = linode.ip.list { |network| network['ispublic'] == 1 }

          break if linode && public_network
        end
        info("Linode IP: #{public_network['ipaddress']}")
        
        if private_network
         info("Linode Private IP: #{private_network['ipaddress']}")
        end
        
        linode ||= @client.linode.list(linodeid: state[:linode_id])

        wait_for_sshd(state[:hostname]); print "(ssh ready)\n"
        debug("linode:create #{state[:hostname]}")
      end

      def destroy(state)
        return if state[:linode_id].nil?

        # A new linode cannot be destroyed before it is active
        # Retry destroying the linode as long as its status is "new"
        loop do
          linode = @client.linode.list(linodeid: state[:linode_id])

          break if !linode
          if linode.status != 'new'
            @client.linode.delete(linodeid: state[:linode_id])
            break
          end

          info("Waiting on Linode <#{state[:linode_id]}> to be active to destroy it, retrying in 8 seconds")
          sleep 8
        end

        info("Linode <#{state[:linode_id]}> destroyed.")
        state.delete(:linode_id)
        state.delete(:hostname)
      end
      
      private
      
      # generate a random name if server name is empty
      def get_server_name
        "kitchen_linode-#{rand.to_s.split('.')[1]}"
      end
      
    end
  end
end

# vim: ai et ts=2 sts=2 sw=2 ft=ruby
