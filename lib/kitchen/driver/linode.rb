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

require "securerandom" unless defined?(SecureRandom)
require "kitchen"
require "fog/linode"
require "retryable" unless defined?(Retryable)
require_relative "linode_version"

module Kitchen

  module Driver
    # Linode driver for Kitchen.
    #
    # @author Brett Taylor <btaylor@linode.com>
    class Linode < Kitchen::Driver::Base
      kitchen_driver_api_version 2
      plugin_version Kitchen::Driver::LINODE_VERSION

      default_config :password do
        SecureRandom.uuid
      end
      default_config :disable_ssh_password, true
      default_config :label, nil
      default_config :tags, ["kitchen"]
      default_config :hostname, nil
      default_config :image, nil
      default_config :region, ENV["LINODE_REGION"] || "us-east"
      default_config :type, "g6-nanode-1"
      default_config :kernel, "linode/grub2"
      default_config :api_retries, 5
      default_config :authorized_users, ENV["LINODE_AUTH_USERS"].to_s.split(",")

      default_config :private_key_path do
        [
          File.expand_path("~/.ssh/id_rsa"),
          File.expand_path("~/.ssh/id_dsa"),
          File.expand_path("~/.ssh/identity"),
          File.expand_path("~/.ssh/id_ecdsa"),
        ].find { |path| File.exist?(path) }
      end

      default_config :public_key_path do |driver|
        if driver[:private_key_path] && File.exist?(driver[:private_key_path] + ".pub")
          driver[:private_key_path] + ".pub"
        end
      end

      default_config :linode_token, ENV["LINODE_TOKEN"]

      required_config :linode_token

      def initialize(config)
        super
        # callback to check if we can retry
        retry_exception_callback = lambda do |exception|
          if exception.class == Excon::Error::TooManyRequests
            # add a random value between 2 and 20 to the sleep to splay retries
            sleep_time = exception.response.headers["Retry-After"].to_i + rand(2..20)
            warn("Rate limit encountered, sleeping #{sleep_time} seconds for it to expire.")
            sleep(sleep_time)
          end
        end
        log_method = lambda do |retries, exception|
          warn("[Attempt ##{retries}] Retrying because [#{exception.class}]")
        end
        # configure to retry on timeouts and rate limits by default
        Retryable.configure do |retry_config|
          retry_config.log_method   = log_method
          retry_config.exception_cb = retry_exception_callback
          retry_config.on           = [Excon::Error::Timeout,
                                       Excon::Error::RequestTimeout,
                                       Excon::Error::TooManyRequests]
          retry_config.tries        = config[:api_retries]
          retry_config.sleep        = lambda { |n| 2**n } # sleep 1, 2, 4, etc. each try
        end
      end

      def create(state)
        # create and boot server
        if state[:linode_id]
          info "Linode <#{state[:linode_id]}, #{state[:linode_label]}> already exists."
          return
        end

        config_hostname
        config_label
        server = create_server

        # assign the machine id for reference in other commands
        update_state(state, server)
        info("Linode <#{state[:linode_id]}, #{state[:linode_label]}> created.")
        info("Waiting for linode to boot...")
        server.wait_for { server.status == "running" }
        instance.transport.connection(state).wait_until_ready
        info("Linode <#{state[:linode_id]}, #{state[:linode_label]}> ready.")
        setup_server(state) if bourne_shell?
      rescue Fog::Errors::Error, Excon::Errors::Error => ex
        error("Failed to create server: #{ex.class} - #{ex.message}")
        raise ActionFailed, ex.message
      end

      def destroy(state)
        return if state[:linode_id].nil?

        begin
          Retryable.retryable do
            server = compute.servers.get(state[:linode_id])
            server.destroy
          end
          info("Linode <#{state[:linode_id]}, #{state[:linode_label]}> destroyed.")
        rescue Excon::Error::NotFound
          info("Linode <#{state[:linode_id]}, #{state[:linode_label]}> not found.")
        end
        state.delete(:linode_id)
        state.delete(:linode_label)
        state.delete(:pub_ip)
      end

      private

      def compute
        Fog::Compute.new(provider: :linode, linode_token: config[:linode_token])
      end

      def get_region
        region = nil
        Retryable.retryable do
          region = compute.regions.find { |x| x.id == config[:region] }
        end
        raise(UserError, "No match for region: #{config[:region]}") if region.nil?

        info "Got region: #{region.id}..."
        region.id
      end

      def get_type
        type = nil
        Retryable.retryable do
          type = compute.types.find { |x| x.id == config[:type] }
        end
        raise(UserError, "No match for type: #{config[:type]}") if type.nil?

        info "Got type: #{type.id}..."
        type.id
      end

      def get_image
        if config[:image].nil?
          image_id = instance.platform.name
        else
          image_id = config[:image]
        end
        image = nil
        Retryable.retryable do
          image = compute.images.find { |x| x.id == image_id }
        end
        raise(UserError, "No match for image: #{config[:image]}") if image.nil?

        info "Got image: #{image.id}..."
        image.id
      end

      def get_kernel
        kernel = nil
        Retryable.retryable do
          kernel = compute.kernels.find { |x| x.id == config[:kernel] }
        end
        raise(UserError, "No match for kernel: #{config[:kernel]}") if kernel.nil?

        info "Got kernel: #{kernel.id}..."
        kernel.id
      end

      # generate a unique label
      def generate_unique_label
        # Try to generate a unique suffix and make sure nothing else on the account
        # has the same label.
        # The iterator is a randomized list from 0 to 999.
        (0..999).to_a.sample(1000).each do |suffix|
          label = "#{config[:label]}_#{"%03d" % suffix}"
          Retryable.retryable do
            if compute.servers.find { |server| server.label == label }.nil?
              return label
            end
          end
        end
        # If we're here that means we couldn't make a unique label with the
        # given prefix. Yell at the user that they need to clean up their
        # account.
        error(
          "Unable to generate a unique label with prefix #{config[:label]}. " \
          "Might need to cleanup your account."
        )
        raise(UserError, "Unable to generate a unique label.")
      end

      def create_server
        region = get_region
        type = get_type
        image = get_image
        kernel = get_kernel
        authorized_keys = config[:public_key_path] ? [open(config[:public_key_path]).read.strip] : []
        # callback to check if we can retry
        create_exception_callback = lambda do |exception|
          unless exception.response.body.include? "Label must be unique"
            # we want to float this to the user instead of retrying
            raise exception
          end

          info("Got [#{exception.class}] due to non-unique label when creating server.")
          info("Will try again with a new label if we can.")
        end
        # submit new linode request
        Retryable.retryable(
          on: [Excon::Error::BadRequest],
          tries: config[:api_retries],
          exception_cb: create_exception_callback,
          log_method: proc {}
        ) do
          # This will retry if we get a response that the label must be
          # unique. We wrap both of these in a retry so we generate a
          # new label when we try again.
          label = generate_unique_label
          info("Creating Linode - #{label}")
          Retryable.retryable do
            compute.servers.create(
              region: region,
              type: type,
              label: label,
              tags: config[:tags],
              image: image,
              kernel: kernel,
              root_pass: config[:password],
              authorized_keys: authorized_keys,
              authorized_users: config[:authorized_users]
            )
          end
        end
      end

      def setup_server(state)
        info "Setting hostname..."
        shortname = "#{config[:hostname].split(".")[0]}"
        hostsfile = "127.0.0.1 #{config[:hostname]} #{shortname} " \
        "localhost\n::1 #{config[:hostname]} #{shortname} localhost"
        instance.transport.connection(state).execute(
            "echo '#{hostsfile}' > /etc/hosts &&" \
            "hostnamectl set-hostname #{config[:hostname]}"
          )
        if config[:private_key_path] && config[:public_key_path] && config[:disable_ssh_password]
          info "Disabling SSH password login..."
          # Disable password auth and bounce SSH
          instance.transport.connection(state).execute(
            "sed -i 's/^PasswordAuthentication .*$/PasswordAuthentication no/' /etc/ssh/sshd_config &&" +
            "systemctl restart ssh &> /dev/null || " +      # Ubuntu, Debian, most systemd distros
            "systemctl restart sshd &> /dev/null || " +     # CentOS 7+
            "/etc/init.d/sshd restart &> /dev/null || " +   # OpenRC (Gentoo, Alpine) and sysvinit
            "/etc/init.d/ssh restart &> /dev/null || " +    # Other OpenRC and sysvinit distros
            "/etc/rc.d/rc.sshd restart &> /dev/null"        # Slackware
          )
        end
        info "Done setting up server."
      end

      # Set the proper server name in the config
      def config_label
        unless config[:label]
          basename = config[:kitchen_root] ? File.basename(config[:kitchen_root]) : "job"
          jobname = ENV["JOB_NAME"] || ENV["GITHUB_JOB"] || basename
          config[:label] = "kitchen-#{jobname}-#{instance.name}"
        end
        # cut to fit Linode 64 character maximum
        # we trim to 60 so we can add '_' with a random 3 digit suffix later
        if config[:label].tr(" /", "_").size >= 60
          config[:label] = "#{config[:label][0..59]}"
        end
      end

      # Set the proper server hostname
      def config_hostname
        if config[:hostname].nil?
          if config[:label]
            config[:hostname] = "#{config[:label]}"
          else
            config[:hostname] = "#{instance.name}"
          end
        end
      end

      def update_state(state, server)
        state[:linode_id] = server.id
        state[:linode_label] = server.label
        state[:hostname] = server.ipv4[0]
        if config[:private_key_path] && config[:public_key_path]
          state[:ssh_key] = config[:private_key_path]
        else
          warn "Using SSH password auth, some things may not work."
          state[:password] = config[:password]
        end
      end
    end
  end
end
