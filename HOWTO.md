# How to migrate from Hipchat to Mattermost with Hipmost

Migrating from Hipchat to Mattermost is a bit of a process, but if you know what to do then it's fairly straightforward. We'll describe some steps of what to do in this document, taking from [Mattermost's own guidelines.](https://mattermost.com/atlassian/#hipchat-migration) *Credit goes to Mattermost for the content which they wrote.*

## Step 1: Set up your Mattermost Instance

1. Download the [latest version of Mattermost](https://about.mattermost.com/download/).
2. [Deploy Mattermost](https://docs.mattermost.com/guides/administrator.html#installing-mattermost) in your environment using the configuration that meets your organization’s needs for performance and scalability.
3. [Request a Trial](https://mattermost.com/trial) of Mattermost Enterprise for [advanced features](https://mattermost.com/pricing).

Feel free to [submit an issue](https://github.com/orbitalimpact/hipmost/issues/new) or visit Mattermost's [troubleshooting forum](https://forum.mattermost.org/t/how-to-use-the-troubleshooting-forum/150) for help.

## Step 2: Export your data from HipChat

### Situation 1:

If your Hipchat instance is hosted on hipchat.com (i.e., **not** self-hosted) then you need to request your data from Atlassian. Go to [this page,](https://support.atlassian.com/hipchat/) log in with your Hipchat account information, submit a ticket via the `Contact Support` button, and explain that you wish to obtain a copy of your team's data. After some days, they should give you an AES-encrypted tarball containing your data (the file will have the extension `.tar.gz.aes`). [Here is another document](https://confluence.atlassian.com/hipchatkb/unable-to-decrypt-file-while-importing-into-hipchat-server-756777042.html) explaining how to manually decrypt your tarball at the command line.

### Situation 2:

These are the steps to follow if you're using Hipchat Server or Hipchat Data Center, as given by Mattermost.

(i.e., what to do if you **are** self-hosted)

If you’re able to upgrade HipChat Server or HipChat Data Center to the latest version, we recommend using Group Export Dashboard to export your data. If you’re unable to upgrade, see Command Line Interface procedure below.

*Using the Group Export Dashboard*:

1. Log in to your Hipchat Server or HipChat Server instance (e.g., hipchat.yourcompany.com)
2. Click on **Server Admin > Export**.
3. Select the data to export.
4. In the Password and Confirm Password fields, create a password to protect your archive files. (Store this password as it is not saved anywhere else.)
5. Click Export. Once the export is done, you will receive an email with a link to download the file.

*If you’re unable to use the Group Export Dashboard, use the Command Line Interface to export:*

1. Go to CLI.
2. Enter `hipchat export --export -p your_password`
3. Once the export is done, you will receive an email with a link to download the file.

*More detailed instructions can be found at https://confluence.atlassian.com/hipchatdc3/export-data-from-hipchat-data-center-913476832.html.*

## Step 3: Use Hipmost to convert your data

After you've received your data, decrypted it, and extracted it to a folder, you may then use `hipmost` to convert your data for importation into Mattermost. If you name your folder `data`, then you can simply use `hipmost rooms import "Example Room" "Mattermost Team":"Mattermost Channel"`. Of course, substitute whatever the actual name of your room, channel, and team is in their respective fields. Furthermore, you may use the `-p` option to set a different path to your data. More usage options [in the `Usage` section of README.md.](./README.md#usage)

After you execute the `hipmost` command, you should have a file entitled `Room Name.jsonl` in the current directory which is ready to be imported into Mattermost.

## Step 4: Import your data into Mattermost

1. Follow the [Mattermost Bulk Load Tool](https://docs.mattermost.com/deployment/bulk-loading.html) guide to import your data into Mattermost.
  a. Note: Efforts are underway to source scripts from the Mattermost community to further automate this step. If you’re interested in contributing, please contact Mattermost at [info@mattermost.com](info@mattermost.com), Twitter or Mattermost forums at https://forum.mattermost.org
2. Alternatively, [contact Mattermost](https://mattermost.com/contact-us) for partner recommendations for your region to assist in your import.

If you encounter any troubles along the way, please feel free to [submit an issue](https://github.com/orbitalimpact/hipmost/issues/new) and let us know what problem you're having.