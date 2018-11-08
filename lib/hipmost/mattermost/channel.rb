module Hipmost
  module Mattermost
    class Channel
      def self.from_hipchat(room, name:, team: )
        raise "Must have a room" if room.nil?

        new(name:          name,
            type:          room.private? ? "P" : "O",
            display_name:  room.display_name,
            header:        room.topic,
            team:          team)
      end

      def initialize(name:, team:, display_name:, type:, header:)
        @name         = name.downcase.gsub(/\s/, "-")
                             .gsub("[", "").gsub("]", "")
                             .gsub("(", "").gsub(")", "")
                             .gsub("{", "").gsub("}", "")
                             .gsub("<", "-").gsub(">", "-")
                             .gsub("#", "")
                             .gsub("/", "-")
                             .gsub(".", "-")
                             .gsub("&", "-")
                             .gsub("'", "-")
                             .gsub(/[-]*$/, "")
        @team         = team
        @display_name = display_name.gsub("\\", "\\\\\\")
                                    .gsub("\"", "\\\\\"")
        @type         = type
        @header       = header.gsub("\\", "\\\\\\")
                              .gsub("\"", "\\\\\"")
      end
      attr_reader :name

      def to_jsonl
        %[{ "type": "channel", "channel": { "team": "#{@team.name}", "name": "#@name", "display_name": "#@display_name", "type": "#@type", "header": "#@header" } }]
      end
    end
  end
end
