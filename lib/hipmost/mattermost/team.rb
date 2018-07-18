module Hipmost
  module Mattermost
    class Team
      def initialize(display_name)
        @display_name = display_name
      end
      attr_reader :display_name

      def to_jsonl
        %[{ "type": "team", "team": { "display_name": "#@display_name", "diplay_display_name": "#@display_name", "type": "I", "description": "#@display_name", "allow_open_invite": false } }]
      end

      def name
        return "oi" if display_name == "Orbital Impact"
      end
    end
  end
end
