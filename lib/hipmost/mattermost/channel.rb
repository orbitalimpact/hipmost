module Hipmost
  module Mattermost
    class Channel
      def self.from_hipchat(room, name:, team: )
        new(name:          name,
            type:          room.private? ? "P" : "O",
            display_name:  room.display_name,
            header:        room.topic,
            team:          team)
      end

      def initialize(name:, team:, display_name:, type:, header:)
        @name         = name
        @team         = team
        @display_name = display_name
        @type         = type
        @header       = header
      end
      attr_reader :name

      def to_jsonl
        %[{ "type": "channel", "channel": { "team": "#{@team.name}", "name": "#@name", "display_name": "#@display_name", "type": "#@type", "header": "#@header" } }]
      end
    end
  end
end
