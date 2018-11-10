# Hipmost

[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=AYNCCNVFYPKXW)

Hipmost is a tool to migrate your Hipchat history to Mattermost. It parses your Hipchat export and generates a file to be imported on a Mattermost server. After generating this file, please see [the Mattermost documentation](https://docs.mattermost.com/deployment/bulk-loading.html) for how to import it on your server.

## Installation

    $ gem install hipmost

## Getting started

See [HOWTO.md](./HOWTO.md) for a step-by-step guide for the entire process. It covers everything from how to get your data from Hipchat, and finally, how to get that data into Mattermost.

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

    users
    Form: users - Exports the list of users to Users.jsonl This helps fix user not found errors during import.  This is especially important if your users are no always members of the rooms.
    
    --------

    Examples:
    $ hipmost room import "Orbital Impact" "Orbital Impact":"General"
    $ hipmost public import "Orbital Impact" "Orbital Impact":"General" -p data_folder
    $ hipmost private list      # List all private chat rooms
    $ hipmost private import    # Import all private chats
    $ hipmost users
    $ hipmost -v rooms import "Orbital Impact" "Orbital Impact":"General"

    -p, --path [PATH]     Path to Hipchat data folder (Default: "./data")
    -v, --[no-]verbose    Run verbosely

## Generating Commands
The file Commands.ods can be used to generate your import commands.


## Known Bugs
See the [KNOWN-BUGS.md](./KNOWN-BUGS.md) file for discussion of known problems, workarounds, and potential improvements. This is also a good place to start if you're interested in contributing.

## Contributing

Bug reports and pull requests are welcome. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Ruby code of conduct.](https://www.ruby-lang.org/en/conduct/)

Also, [here is a great reference for Hipchat's data format](https://confluence.atlassian.com/hipchatkb/exporting-from-hipchat-server-or-data-center-for-data-portability-950821555.html) and [here is a great reference for how Mattermost's data format.](https://docs.mattermost.com/deployment/bulk-loading.html#data-format) These are highly useful for aspiring contributors.

## License

The gem is available as open source under the terms of the [MIT License.](https://opensource.org/licenses/MIT)

## Code of Conduct

Everyone interacting in the Hipmost project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct.](./CODE_OF_CONDUCT.md)

## Donation
If this project has helped you or your team, a donation would be appreciated and will help keep the project alive :)

[![paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=AYNCCNVFYPKXW)
