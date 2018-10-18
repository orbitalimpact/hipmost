# Hipmost

[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=AYNCCNVFYPKXW)

Hipmost is a tool to migrate your Hipchat history to Mattermost. It parses your Hipchat export and generates a file to be imported on a Mattermost server. After generating this file, please see [the Mattermost documentation](https://docs.mattermost.com/deployment/bulk-loading.html) for how to import it on your server.

## Installation

For now:

    $ gem install specific_install
    $ gem specific_install -l https://github.com/orbitalimpact/hipmost.git

Eventually, it might be this:

    $ gem install hipmost

## Usage

    Usage: hipmost [options] [command]

    Commands:

    public (AKA: `room' or `rooms')
    Form: public [import|list] [room names] - Import or list public Hipchat rooms

    [room names] must be at least one pair composed by "Hipchat room name" and "Mattermost team":"Mattermost channel".
    The Mattermost team or channel can be the part visible in the URL path, such as "town-square", or it can be the plain-English name, such as "General"

    --------

    private (AKA: `direct')
    Form: private [import|list]  - Import or list private chats

    --------

    Examples:
    $ hipmost room import "Orbital Impact" "Orbital Impact":"General"
    $ hipmost public import "Orbital Impact" "Orbital Impact":"General" -p data_folder
    $ hipmost private list
    $ hipmost -v rooms import "Orbital Impact" "Orbital Impact":"General"

    -p, --path [PATH]     Path to Hipchat data folder (Default: "./data")
    -v, --[no-]verbose    Run verbosely

## Known Bugs
See the [KNOWN-BUGS.md](./KNOWN-BUGS.md) file for discussion of known problems, workarounds, and potential improvements. This is also a good place to start if you're interested in contributing.

## Contributing

Bug reports and pull requests are welcome. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Ruby code of conduct.](https://www.ruby-lang.org/en/conduct/)

## License

The gem is available as open source under the terms of the [MIT License.](https://opensource.org/licenses/MIT)

## Code of Conduct

Everyone interacting in the Hipmost project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct.](./CODE_OF_CONDUCT.md)

## Donation
If this project has helped you or your team, a donation would be appreciated and will help keep the project alive :)

[![paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=AYNCCNVFYPKXW)
