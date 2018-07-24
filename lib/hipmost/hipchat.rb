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
        @rooms ||= RoomRepository.new($path).tap(&:load)
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

      def direct_posts(file, verbose)
        i = 1 if verbose

        Dir[$path.join("users", "**", "*.json")].each do |file_path|
          puts "Opening 1-on-1 room at #{file_path}..." if verbose
          json = JSON.parse(File.read(file_path))
          puts "Successfully parsed file at #{file_path}" if verbose

          puts "Examining messages in this file..." if verbose

          json.each do |message|
            if verbose
              print "On post #{i}\r"
              i += 1
            end

            msg       = message["PrivateUserMessage"]
            sender    = users[msg["sender"]["id"]]
            receiver  = users[msg["receiver"]["id"]]
            message   = msg["message"]
            create_at = DateTime.strptime(msg["timestamp"]).to_time.to_i*1000

            members = [ sender.username, receiver.username ] .sort

            file.puts(%[{ "type": "direct_post", "direct_post": { "channel_members": #{members.inspect}, "user": "#{sender.username}", "message": "#{message}", "create_at": #{create_at} } }])
          end

          if verbose
            print "\n"
            puts "Successfully wrote data for that 1-on-1 room\n\n"
          end
        end
      end
    end
  end
end
