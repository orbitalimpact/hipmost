require 'json'
require 'date'

require_relative "hipchat/user_repository"
require_relative "hipchat/room_repository"
require_relative "hipchat/post_repository"

module Hipmost
  module Hipchat
    class << self
      def users
        @users ||= UserRepository.load_from($path)
      end

      def rooms
        @rooms ||= RoomRepository.load_from($path)
      end

      def direct_channels
        Dir[$path.join("users", "**", "*.json")].flat_map do |file_path|
          json = JSON.parse(File.read(file_path))
          json.map do |message|
            msg      = message["PrivateUserMessage"]
            sender   = users[msg["sender"]["id"]]
            receiver = users[msg["receiver"]["id"]]
            [sender.username, receiver.username].sort
          end
        end.uniq
      end

      def direct_posts(file)
        Dir[$path.join("users", "**", "*.json")].each do |file_path|
          json = JSON.parse(File.read(file_path))
          json.each do |message|
            msg       = message["PrivateUserMessage"]
            sender    = users[msg["sender"]["id"]]
            receiver  = users[msg["receiver"]["id"]]
            message   = msg["message"]
            create_at = DateTime.strptime(msg["timestamp"]).to_time.to_i

            members = [ sender.username, receiver.username ] .sort

            file.puts(%[{ "type": "direct_post", "direct_post": { "channel_members": #{members.inspect}, "user": "#{sender.username}", "message": "#{message}", "create_at": "#{create_at}" } }])
          end
        end
      end
    end
  end
end
