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
require "fog/json"
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

      default_config :linode_token do
        ENV["LINODE_TOKEN"]
      end
      default_config :password do
        ENV["LINODE_PASSWORD"] || SecureRandom.uuid
      end
      default_config :label, nil
      default_config :tags, ["kitchen"]
      default_config :hostname, nil
      default_config :image, nil
      default_config :region do
        ENV["LINODE_REGION"] || "us-east"
      end
      default_config :type, "g6-nanode-1"
      default_config :stackscript_id, nil
      default_config :stackscript_data, nil
      default_config :swap_size, nil
      default_config :private_ip, false
      default_config :authorized_users do
        ENV["LINODE_AUTH_USERS"].to_s.split(",")
      end
      default_config :private_key_path do
        ENV["LINODE_PRIVATE_KEY"] || [
          File.expand_path("~/.ssh/id_rsa"),
          File.expand_path("~/.ssh/id_dsa"),
          File.expand_path("~/.ssh/identity"),
          File.expand_path("~/.ssh/id_ecdsa"),
        ].find { |path| File.exist?(path) }
      end
      expand_path_for :private_key_path
      default_config :public_key_path do |driver|
        if driver[:private_key_path] && File.exist?(driver[:private_key_path] + ".pub")
          driver[:private_key_path] + ".pub"
        end
      end
      expand_path_for :public_key_path
      default_config :disable_ssh_password, true
      default_config :api_retries, 5

      required_config :linode_token

      def initialize(config)
        super
        # configure to retry on timeouts and rate limits by default
        Retryable.configure do |retry_config|
          retry_config.log_method   = method(:retry_log_method)
          retry_config.exception_cb = method(:retry_exception_callback)
          retry_config.on           = [Excon::Error::Timeout,
                                       Excon::Error::RequestTimeout,
                                       Excon::Error::TooManyRequests]
          retry_config.tries        = config[:api_retries]
          retry_config.sleep        = lambda { |n| 2**n } # sleep 1, 2, 4, etc. each try
        end
      end

      # create and boot server
      def create(state)
        return if state[:linode_id]

        config_hostname
        config_label
        server = create_server

        update_state(state, server)
        info "Linode <#{state[:linode_id]}, #{state[:linode_label]}> created."
        info "Waiting for linode to boot..."
        server.wait_for { server.status == "running" }
        instance.transport.connection(state).wait_until_ready
        info "Linode <#{state[:linode_id]}, #{state[:linode_label]}> ready."
        setup_server(state) if bourne_shell?
      rescue Fog::Errors::Error, Excon::Errors::Error => ex
        error "Failed to create server: #{ex.class} - #{ex.message}"
        raise ActionFailed, ex.message
      end

      def destroy(state)
        return if state[:linode_id].nil?

        begin
          Retryable.retryable do
            server = compute.servers.get(state[:linode_id])
            server.destroy
          end
          info "Linode <#{state[:linode_id]}, #{state[:linode_label]}> destroyed."
        rescue Excon::Error::NotFound
          info "Linode <#{state[:linode_id]}, #{state[:linode_label]}> not found."
        end
        state.delete(:linode_id)
        state.delete(:linode_label)
        state.delete(:pub_ip)
      end

      private

      def compute
        Fog::Compute.new(provider: :linode, linode_token: config[:linode_token])
      end

      # generate a unique label
      def generate_unique_label
        # Try to generate a unique suffix and make sure nothing else on the account
        # has the same label.
        # The iterator is a randomized list from 0 to 999.
        (0..999).to_a.sample(1000).each do |suffix|
          label = "#{config[:label]}_#{"%03d" % suffix}"
          Retryable.retryable do
            return label if compute.servers.find { |server| server.label == label }.nil?
          end
        end
        # If we're here that means we couldn't make a unique label with the
        # given prefix. Inform the user that they need to clean up their
        # account.
        error "Unable to generate a unique label with prefix #{config[:label]}."
        error "Might need to cleanup your account."
        raise(UserError, "Unable to generate a unique label.")
      end

      def create_server
        # submit new linode request
        Retryable.retryable(
          on: [Excon::Error::BadRequest],
          tries: config[:api_retries],
          exception_cb: method(:create_server_exception_callback),
          log_method: proc {}
        ) do
          # This will retry if we get a response that the label must be
          # unique. We wrap both of these in a retry so we generate a
          # new label when we try again.
          label = generate_unique_label
          image = config[:image] || instance.platform.name
          info "Creating Linode:"
          info "  label:  #{label}"
          info "  region: #{config[:region]}"
          info "  image: #{image}"
          info "  type: #{config[:type]}"
          info "  tags: #{config[:tags]}"
          info "  swap_size: #{config[:swap_size]}" if config[:swap_size]
          info "  private_ip: #{config[:private_ip]}" if config[:private_ip]
          info "  stackscript_id: #{config[:stackscript_id]}" if config[:stackscript_id]
          Retryable.retryable do
            compute.servers.create(
              label: label,
              region: config[:region],
              image: image,
              type: config[:type],
              tags: config[:tags],
              stackscript_id: config[:stackscript_id],
              stackscript_data: config[:stackscript_data],
              swap_size: config[:swap_size],
              private_ip: config[:private_ip],
              root_pass: config[:password],
              authorized_keys: config[:public_key_path] ? [open(config[:public_key_path]).read.strip] : [],
              authorized_users: config[:authorized_users]
            )
          end
        end
      end

      # post build server setup, including configuring the hostname
      def setup_server(state)
        info "Setting hostname..."
        shortname = "#{config[:hostname].split(".")[0]}"
        instance.transport.connection(state).execute(
          "echo '127.0.0.1 #{config[:hostname]} #{shortname} localhost\n" +
          "::1 #{config[:hostname]} #{shortname} localhost' > /etc/hosts && " +
          "hostnamectl set-hostname #{config[:hostname]} &> /dev/null || " +
          "hostname #{config[:hostname]} &> /dev/null"
        )
        if config[:private_key_path] && config[:public_key_path] && config[:disable_ssh_password]
          # Disable password auth and bounce SSH
          info "Disabling SSH password login..."
          instance.transport.connection(state).execute(
            "sed -ri 's/^#?PasswordAuthentication .*$/PasswordAuthentication no/' /etc/ssh/sshd_config &&" +
            "systemctl restart ssh &> /dev/null || " +     # Ubuntu, Debian, most systemd distros
            "systemctl restart sshd &> /dev/null || " +    # CentOS 7+
            "/etc/init.d/sshd restart &> /dev/null || " +  # OpenRC (Gentoo, Alpine) and sysvinit
            "/etc/init.d/ssh restart &> /dev/null || " +   # Other OpenRC and sysvinit distros
            "/etc/rc.d/rc.sshd restart &> /dev/null && " + # Slackware
            "sleep 1" # Sleep because Slackware's rc script doesn't start SSH back up without it
          )
        end
        info "Done setting up server."
      end

      # generate a label prefix if none is supplied and ensure it's less than
      # the character limit.
      def config_label
        unless config[:label]
          basename = config[:kitchen_root] ? File.basename(config[:kitchen_root]) : "job"
          jobname = ENV["JOB_NAME"] || ENV["GITHUB_JOB"] || basename
          config[:label] = "kitchen-#{jobname}-#{instance.name}"
        end
        config[:label] = config[:label].tr(" /", "_")
        # cut to fit Linode 64 character maximum
        # we trim to 60 so we can add '_' with a random 3 digit suffix later
        if config[:label].size >= 60
          config[:label] = "#{config[:label][0..59]}"
        end
      end

      # configure the hostname either by the provided label or the instance name
      def config_hostname
        if config[:hostname].nil?
          if config[:label]
            config[:hostname] = "#{config[:label]}"
          else
            config[:hostname] = "#{instance.name}"
          end
        end
      end

      # update the kitchen state with the returned server
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

      # retry exception callback to check if we need to wait for a rate limit
      def retry_exception_callback(exception)
        if exception.class == Excon::Error::TooManyRequests
          # add a random value between 2 and 20 to the sleep to splay retries
          sleep_time = exception.response.headers["Retry-After"].to_i + rand(2..20)
          warn "Rate limit encountered, sleeping #{sleep_time} seconds for it to expire."
          sleep(sleep_time)
        end
      end

      # retry logging callback to print a message when we're retrying a request
      def retry_log_method(retries, exception)
        warn "[Attempt ##{retries}] Retrying because [#{exception.class}]"
      end

      # create_server callback to check if we can retry the request
      def create_server_exception_callback(exception)
        unless exception.response.body.include? "Label must be unique"
          # not a retriable error.
          # decode our error(s) and print for the user, then raise a UserError.
          begin
            resp_errors = Fog::JSON.decode(exception.response.body)["errors"]
            resp_errors.each do |resp_error|
              error "error:"
              resp_error.each do |key, value|
                error "  #{key}: #{value}"
              end
            end
          rescue
            # something went wrong with decoding and pretty-printing the error
            # just raise the original exception.
            raise exception
          end
          raise(UserError, "Bad request when creating server.")
        end
        info "Got [#{exception.class}] due to non-unique label when creating server."
        info "Will try again with a new label if we can."
      end
    end
  end
end
