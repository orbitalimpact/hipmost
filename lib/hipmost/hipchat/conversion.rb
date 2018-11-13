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

    def self.convert_formatting_to_markdown_messages(message)
      if message
	if message.lines.count == 1
          result = Array.new
	  result.push message
	end

        if message.start_with?("/code")
	  result = split_formatted_lines("/code", message.sub("/code", ""), 3500)
        elsif message.start_with?("/quote")
	  result = split_formatted_lines("/quote", message.sub("/quote", ""), 3500)
	else
	  result = split_formatted_lines("", message, 3500)
        end

	result.each do |messagePart|
          puts " convert_formatting_to_markdown_messages #{messagePart}"
          convert_formatting_to_markdown(messagePart)
          puts " convert_formatting_to_markdown_messages #{messagePart}"
	end
      end
    end

    def self.split_formatted_lines (prefix, message, maxLength)
      result = Array.new
      currentLine = ""

      message.lines.each do |line|
        if currentLine.length + line.length > maxLength
	  result.push prefix + "\n" + currentLine
	  currentLine = line
	else
          currentLine = currentLine + "\n" + line
	end
      end

      result.push prefix + "\n" + currentLine

      return result
    end
  end
end
