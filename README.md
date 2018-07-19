# Hipmost

Hipmost is a tool to migrate your Hipchat history to Mattermost, it
parses your hipchat export and generates a file to be imported on
Mattermost

## Installation

    $ gem install hipmost

## Usage

    Usage: hipmost [options] [rooms...]

    [rooms] must be a pair composed by "Hipchat channel name" and "Mattermost team":"Mattermost channel"

    Example: hipmost Geneal Team:"Town Center"

    -p, --path [PATH]                Data path (Default: "./data")
    -v, --[no-]verbose               Run verbose

## Contributing

Bug reports and pull requests are welcome. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Ruby code of conduct.](https://www.ruby-lang.org/en/conduct/)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Hipmost project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct.](https://www.ruby-lang.org/en/conduct/)
