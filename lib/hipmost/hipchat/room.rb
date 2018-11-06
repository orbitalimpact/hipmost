
=begin
  {
    "Room": {
      "created": "2013-05-27T13:29:02+00:00",
      "guest_access_url": null,
      "id": 206455,
      "is_archived": false,
      "members": [
        752160,
        1002528,
        844771,
        340070,
        1017103,
        340825
      ],
      "name": "Orbital Impact",
      "owner": 340070,
      "participants": [],
      "privacy": "private",
      "topic": "Welcome! Send this link to coworkers who need accounts: https://www.hipchat.com/invite/50371/3c380f069e21ba92e3441c57952e4ed0"
    }
  },
=end

module Hipmost
  module Hipchat
    class Room
      def initialize(attrs)
        @id           = attrs["id"]
        @name         = attrs["name"].gsub(/\s/, "-")
                                     .gsub("[", "").gsub("]", "").downcase
        @display_name = attrs["name"]
        @topic        = attrs["topic"]
        @attrs        = attrs
      end
      attr_reader :id, :attrs, :name, :display_name, :topic
      attr_accessor :team, :channel

      def private?
        privacy == "private"
      end

      def users
        @users ||= attrs["members"].map{|uid| Hipchat.users[uid] }
      end

      def posts
        @posts ||= PostRepository.for_room(self)
      end

      def method_missing(method)
        attrs[method.to_s]
      end

    end
  end
end
