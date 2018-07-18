require 'pathname'
require "hipmost/version"
require "hipmost/hipchat"
require "hipmost/mattermost"

module Hipmost
  class CLI
    def self.run(args)
      new(**args).run
    end

    def initialize(path:, rooms:)
      $path    = Pathname.new(path).expand_path
      @outpath = $path.join("..", "data.jsonl").expand_path
      @data    = rooms
      @teams   = []
    end

    def run
      parse_rooms_arg

      save
      true
    end

    def save
      File.open(@outpath, "w") do |jsonl|
        jsonl.puts %[{ "type": "version", "version": 1 }]
        @teams.each {|t| jsonl.puts(t.to_jsonl) }
        @channels.each {|r| jsonl.puts(r.to_jsonl) }

        @rooms.each do |room|
          room.users.each do |user|
            jsonl.puts(user.to_jsonl)
          end
        end

        @rooms.each do |room|
          Hipchat::PostRepository.new(room).tap(&:load).each do |post|
            jsonl.puts(post.to_jsonl)
          end
        end

        Hipchat.direct_channels.each do |members|
          jsonl.puts(%[{ "type": "direct_channel", "direct_channel": { "members": #{members.inspect} }}])
        end

        Hipchat.direct_posts(jsonl)
      end
    end

    def parse_rooms_arg
      @rooms = []
      @channels = []

      @data.each_slice(2).each do |hipchat_room, mattermost_room|
        team, room = mattermost_room.split(":")
        team       = Mattermost::Team.new(team)
        room       = Hipchat.rooms.find_by_name(hipchat_room)
        channel    = Mattermost::Channel.from_hipchat(room, team: team)

        room.team    = team
        room.channel = channel

        @rooms    << room
        @teams    << team
        @channels << channel
      end

      @teams.uniq!
      @rooms.uniq!
      @channels.uniq!
    end
  end
end

