# Misc utilties to do data conversion from Hipchat to Mattermost

module Hipmost
  module Conversion
    def self.convert_formatting_to_markdown(message)
      # According to Hipchat's docs, the only formatting commands which are
      # translatable to Mattermost are /code and /quote.
      # Relevant docs: https://confluence.atlassian.com/hipchat/keyboard-shortcuts-and-slash-commands-749385232.html#Keyboardshortcutsandslashcommands-Slashcommands

      if message
        if message.start_with?("/code") && message.lines.count > 1
          message.sub!("/code", "```\n")
          message << "\n```"
        elsif message.start_with?("/code") && message.lines.count == 1
          message.sub!("/code", "`")
          message << "`"
        end

        if message.start_with?("/quote")
          message.sub!("/quote", ">")
          message.gsub!(/\n\n(.)/, "\n\n> \\1")
        end
      end
    end
  end
end
