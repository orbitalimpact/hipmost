# Hipmost

Hipmost is a tool to migrate your Hipchat history to Mattermost. It parses your Hipchat export and generates a file to be imported on a Mattermost server. After generating this file, please see [the Mattermost documentation](https://docs.mattermost.com/deployment/bulk-loading.html) for how to import it on your server.

## Installation

For now:

    $ gem install specific_install
    $ gem specific_install -l https://gitlab.orbitalimpact.com/gabrielrios/hipmost.git

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
Unfortunately, there are a number of problems which exist that we are presently aware of. We have worked on this project in our spare time, in between work on actual projects. Since we worked on it for free and with our specific data in mind, we have accrued the following bugs and have been unable to devote the time and effort necessary to properly fix all of them (although, some of these bugs have workarounds). We would like to remedy this, yet we could certainly use help in the way of patches or donations. If this project has been helpful to your team or you'd like to improve it to help your team migrate, then please consider submitting patches or donating money so that we can devote more time to this project.

Of course, please do not assume that this list encompasses *all* of the bugs which you may encounter:

- Messages which are of the type `GuestAccessMessage` or `NotificationMessage` are skipped; only `UserMessage`'s and `PrivateUserMessage`'s are processed.
- Verbose mode could be better (i.e., more verbose).
- The CLI could perhaps become easier and more intuitive.
- Documentation should be added beyond simple usage.
- If a file is generated whose name conflicts with an already existing file, then the already existing file will be overwritten.
    - This may be considered a feature, depending on your opinion and use case.
- Sometimes [user objects](https://docs.mattermost.com/deployment/bulk-loading.html#user-object) don't get generated. We're not exactly sure why this happens; unfortunately, it causes the validator to get upset and say something like: `Error importing post. User with username "john_doe" could not be found., SqlUserStore.GetByUsername: We couldn't find an existing account matching your username for this team.`

    - The current workaround is to manually [create the missing user(s)](https://docs.mattermost.com/administration/command-line-tools.html#mattermost-user-create) in the system by hand.


## Contributing

Bug reports and pull requests are welcome. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Ruby code of conduct.](https://www.ruby-lang.org/en/conduct/)

## License

The gem is available as open source under the terms of the [MIT License.](https://opensource.org/licenses/MIT)

## Code of Conduct

Everyone interacting in the Hipmost project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct.](./CODE_OF_CONDUCT.md)
