# Known Bugs
Unfortunately, there are a number of problems which exist that we are presently aware of. We have worked on this project in our spare time, in between work on actual projects. Since we worked on it for free and with our specific data in mind, we have accrued the following bugs and have been unable to devote the time and effort necessary to properly fix all of them (although, some of these bugs have workarounds). We would like to remedy this, yet we could certainly use help in the way of patches or donations. If this project has been helpful to your team or you'd like to improve it to help your team migrate, then please consider submitting patches or donating money so that we can devote more time to this project.

Of course, please do not assume that this list encompasses *all* of the bugs which you may encounter.

Items which are fairly easy to tackle and for which we would like help are marked with "**(help wanted)**"

Without further ado:

## General improvements

- Verbose mode could be better (i.e., more verbose but not too verbose). **(help wanted)**
- The CLI could perhaps become easier and more intuitive. **(help wanted)**
- More thorough documentation is always a good thing. **(help wanted)**

## What gets converted

- Messages which are of the type `TopicRoomMessage`, `ArchiveRoomMessage`, `GuestAccessMessage` or `NotificationMessage` are skipped; only `UserMessage`'s and `PrivateUserMessage`'s are processed.
- Certain Hipchat [slash commands](https://confluence.atlassian.com/hipchat/keyboard-shortcuts-and-slash-commands-749385232.html#Keyboardshortcutsandslashcommands-Slashcommands) are not translated into Mattermost messages because they do not have Mattermost equivalents. This includes: `/clear`, `/me`, `s/`, `#color-hex`. However, we do attempt to translate some slash commands since they have Mattermost equivalents; namely, the formatting slash commands: `/code` and `/quote`.
- We do not currently handle any kind of conversion or importation of files uploaded to Hipchat. E.g., images, documents, media, etc. The reason being that our team relies on external file-hosting services to upload such files to. We found Hipchat's file-hosting to be flaky and not robust. **(help wanted)**
- Some posts may contain old usernames, i.e., a username which someone used in Hipchat that is different than the new username they've chosen for Mattermost. Unfortunately, this cannot be caught by the validator. **(help wanted)**
    - A workaround is to use `sed` or a text editor to find & replace the occurrences of the old username with the new one.

## Potential errors

- Sometimes [user objects](https://docs.mattermost.com/deployment/bulk-loading.html#user-object) don't get generated. We're not exactly sure why this happens; unfortunately, it causes the validator to get upset and say something like: `Error importing post. User with username "john_doe" could not be found., SqlUserStore.GetByUsername: We couldn't find an existing account matching your username for this team.` **(help wanted)**
    - The current workaround is to manually [create the missing user(s)](https://docs.mattermost.com/administration/command-line-tools.html#mattermost-user-create) in the system by hand.
- If a user object *is* generated, but a user's username is now different than what it used to be in Hipchat, Mattermost may complain about them having an insufficient password. E.g.: `User.IsValid: model.user.is_valid.pwd_lowercase_uppercase_number_symbol.app_error` **(help wanted)**
    - A workaround is to remove that user object or to modify the user object to have the right username.

## Questionable behavior

- If a file is generated whose name conflicts with an already existing file, then the already existing file will be overwritten.
    - This may be considered a feature, depending on your opinion and use case.

If you feel like tackling any of these problems, please feel free to submit a pull request or file an issue for discussion. We welcome contributions and are happy to help.