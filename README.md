# <a name="title"></a> Kitchen::Linode

A Test Kitchen Driver for Linode.

## <a name="requirements"></a> Requirements

**TODO:** document any software or library prerequisites that are required to
use this driver. Implement the `#verify_dependencies` method in your Driver
class to enforce these requirements in code, if possible.

## <a name="installation"></a> Installation and Setup

Install the gem file:
```
gem install kitchen-linode
```
Please read the [Driver usage][driver_usage] page for more details.

## <a name="config"></a> Configuration

For many of these, you can specify an ID number, a full name, or a partial name that will try to match something in the list but may not match exactly what you want.
```
LINODE_API_KEY      Linode API Key environment variable, default: nil
:username           ssh user name, default: 'root'
:password           password for user, default: randomly generated hash
:image              Linux distribution, default: nil
:data_center        data center, default: 1
:flavor             linode type/amount of RAM, default: 1
:payment_terms      if you happen to have legacy default: 1
:kernel             Linux kernel, default: 215
:private_key_path   Location of your private key file, default: "~/.ssh/id_rsa"
:public_key_path    Location of your public key file, default: "~/.ssh/id_rsa.pub"
```

## <a name="usage"></a> Usage

First, set your Linode API key in an environment variable:
```
$ export LINODE_API_KEY='myrandomkey123123213h123bh12'
```
Then, create a .kitchen.yml file:
```
---
driver:
  name: linode

provisioner:
  name: salt_solo
  salt_bootstrap_options: -P
  formula: vim
  state_top:
    base:
      "*":
        - vim

platforms:
  - name: debian_jessie
    driver:
      flavor: 1024
      data_center: Dallas
      kernel: 4.0.2-x86_64-linode56
      image: Debian 8.1

suites:
  - name: default

```
then you're ready to run `kitchen test` or `kitchen converge`
```
$ kitchen test
```

### <a name="config-require-chef-omnibus"></a> require\_chef\_omnibus

Determines whether or not a Chef [Omnibus package][chef_omnibus_dl] will be
installed. There are several different behaviors available:

* `true` - the latest release will be installed. Subsequent converges
  will skip re-installing if chef is present.
* `latest` - the latest release will be installed. Subsequent converges
  will always re-install even if chef is present.
* `<VERSION_STRING>` (ex: `10.24.0`) - the desired version string will
  be passed the the install.sh script. Subsequent converges will skip if
  the installed version and the desired version match.
* `false` or `nil` - no chef is installed.

The default value is unset, or `nil`.

## <a name="development"></a> Development

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

## <a name="authors"></a> Authors

Created and maintained by [Brett Taylor][author] (<btaylor@linode.com>)

## <a name="license"></a> License

Apache 2.0 (see [LICENSE][license])


[author]:           https://github.com/ssplatt
[issues]:           https://github.com/ssplatt/kitchen-linode/issues
[license]:          https://github.com/ssplatt/kitchen-linode/blob/master/LICENSE
[repo]:             https://github.com/ssplatt/kitchen-linode
[driver_usage]:     http://docs.kitchen-ci.org/drivers/usage
[chef_omnibus_dl]:  http://www.getchef.com/chef/install/
