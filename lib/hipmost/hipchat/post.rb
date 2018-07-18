require 'date'
module Hipmost
  module Hipchat
    class Post
      def initialize(attrs, room)
        @attrs      = attrs
        @sender     = Hipchat.users[attrs["sender"]["id"]]
        @message    = attrs["message"]
        @created_at = DateTime.strptime(attrs["timestamp"])
        @team       = room.team
        @channel    = room.channel
      end
      attr_reader :team, :channel, :sender

      def to_jsonl
        %[{ "type": "post", "post": { "team": "#{team.name}", "channel": "#{channel.name}", "user": "#{sender.username}", "message": "#@message", "create_at": "#{@created_at.to_time.to_i}" } }]
      end
    end
  end
end

