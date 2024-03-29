# Kitchen::Linode
[![Gem](https://img.shields.io/gem/v/kitchen-linode.svg)](https://rubygems.org/gems/kitchen-linode)
[![Gem](https://img.shields.io/gem/dt/kitchen-linode.svg)](https://rubygems.org/gems/kitchen-linode)
[![Gem](https://img.shields.io/gem/dtv/kitchen-linode.svg)](https://rubygems.org/gems/kitchen-linode)
[![Code Climate](https://codeclimate.com/github/ssplatt/kitchen-linode/badges/gpa.svg)](https://codeclimate.com/github/ssplatt/kitchen-linode)
[![Test Coverage](https://codeclimate.com/github/ssplatt/kitchen-linode/badges/coverage.svg)](https://codeclimate.com/github/ssplatt/kitchen-linode/coverage)
[![CI](https://github.com/ssplatt/kitchen-linode/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/ssplatt/kitchen-linode/actions/workflows/ci.yml)

A Test Kitchen Driver for [Linode](http://www.linode.com).

[![asciicast](https://asciinema.org/a/44348.png)](https://asciinema.org/a/44348)

## Requirements

Requires [Test Kitchen](https://kitchen.ci/) and a [Linode](http://www.linode.com) account.

```sh
gem install test-kitchen
```

## Installation and Setup

The gem file is hosted at [RubyGems](https://rubygems.org/gems/kitchen-linode). To install the gem file, run:

```sh
gem install kitchen-linode
```

Or, install with bundler if you have a Gemfile.

Please read the [Driver usage][driver_usage] page for more details.

## Configuration

For many of these, you can specify an ID number, a full name, or a partial name that will try to match something in the list but may not match exactly what you want.

| Option | Env Var | Default | Description |
|-|-|-|-|
| `linode_token` | `LINODE_TOKEN` | none | Linode API token. Required. |
| `password` | `LINODE_PASSWORD` | Random UUID | Password for root. |
| `label` | none | Auto generated | Label for the server. |
| `tags` | none | `["kitchen"]` | List of tags to set on the server. |
| `hostname` | none | Label if provided, else kitchen instance name | The hostname of the server. |
| `image` | none | Kitchen platform name | Linode image. |
| `region` | `LINODE_REGION` | `us-east` | Linode region. |
| `type` | none | `g6-nanode-1` | Linode type. |
| `stackscript_id` | none | none | StackScript ID to provision the server with. |
| `stackscript_data` | none | none | StackScript data for user defined fields. |
| `swap_size` | none | none | Swap size in MB. |
| `private_ip` | none | `false` | Set to true to add a private IP to the server. |
| `authorized_users` | `LINODE_AUTH_USERS` | `[]` | List of authorized Linode users for seeding SSH keys. Environment variable should be a comma separated list of usernames. |
| `private_key_path` | `LINODE_PRIVATE_KEY` | `~/.ssh/id_rsa`, `~/.ssh/id_dsa`, `~/.ssh/identity`, or `~/.ssh/id_ecdsa`, whichever first exists. | Path to SSH private key that should be used to connect to the server. |
| `public_key_path` | none | Auto inferred based on the `private_key_path` | Path to SSH public key that should be installed on the server. |
| `disable_ssh_password` | none | `true` | When set to `true` and SSH keys are provided password auth for SSH is disabled. |
| `api_retries` | none | `5` | How many times to retry API calls on timeouts or rate limits. |

## Usage

First, set your Linode API token in an environment variable:

```sh
export LINODE_TOKEN='myrandomtoken123123213h123bh12'
```

Then, create a .kitchen.yml file:

```yaml
---
driver:
  name: linode

provisioner:
  name: salt_solo
  formula: vim
  state_top:
    base:
      "*":
        - vim

platforms:
  - name: linode/debian10

suites:
  - name: default
```

then you're ready to run `kitchen test` or `kitchen converge`

```sh
kitchen test
```

If you want to use Vagrant for local tests and Linode for CI tests then you can add the following to your `.kitchen.yml` to automatically switch the driver if the `LINODE_TOKEN` environment variable is set:

```yaml
driver:
  name: <%= ENV['LINODE_TOKEN'] ? 'linode' : 'vagrant' %>

platforms:
  - name: debian-10
    driver:
      box: bento/debian-10
      image: linode/debian10

suites:
  - name: default
```

Note that both the `image` (linode) and the `box` (vagrant) options are supplied in the platform driver configuration.

If you want to change any of the default settings, you can do so in the 'platforms' area:

```yaml
# ...<snip>...
platforms:
  - name: ubuntu_lts
    driver:
      type: g6-standard-2
      region: eu-central
      image: linode/ubuntu20.04
# ...<snip>...
```

## Development

* Source hosted at [GitHub][repo]
* Report issues/questions/feature requests on [GitHub Issues][issues]

Pull requests are very welcome! Make sure your patches are well tested.
Ideally create a topic branch for every separate change you make. For
example:

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Authors

Created and maintained by [Brett Taylor][author] (<btaylor@linode.com>)

## License

Apache 2.0 (see [LICENSE][license])


[author]:           <https://github.com/ssplatt>
[issues]:           <https://github.com/ssplatt/kitchen-linode/issues>
[license]:          <https://github.com/ssplatt/kitchen-linode/blob/master/LICENSE>
[repo]:             <https://github.com/ssplatt/kitchen-linode>
[driver_usage]:     <https://kitchen.ci/docs/reference/configuration/>
