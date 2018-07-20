require 'pathname'
require "hipmost/version"
require "hipmost/hipchat"
require "hipmost/mattermost"

module Hipmost
  class CLI
    def self.run(args)
      new(**args).run
    end

    def initialize(path:, rooms:, verbose: false)
      $path    = Pathname.new(path).expand_path
      @outpath = $path.join("..", "data.jsonl").expand_path
      @data    = rooms
      @verbose = verbose
      @teams   = []
    end

    def run
      puts "Here we go!\n\n" if @verbose
      parse_rooms_arg

      save

      puts "Looks like everything was a success!" if @verbose
      true
    end

    def save
      puts "Opening #{@outpath} for writing..." if @verbose

      File.open(@outpath, "w") do |jsonl|
        puts "Writing version header..." if @verbose
        jsonl.puts %[{ "type": "version", "version": 1 }]

        puts "Writing team info..." if @verbose
        @teams.each {|t| jsonl.puts(t.to_jsonl) }
        puts "Writing channel info..." if @verbose
        @channels.each {|r| jsonl.puts(r.to_jsonl) }

        puts "Writing room members..." if @verbose
        @rooms.each do |room|
          room.users.each do |user|
            jsonl.puts(user.to_jsonl)
          end
        end

        puts "Writing room posts (newest to oldest)..." if @verbose
        i = 1 if @verbose
        j = 1 if @verbose

        @rooms.each do |room|
          if @verbose
            puts "On room #{i}"
            i += 1
          end

          Hipchat::PostRepository.new(room).tap(&:load).each do |post|
            if @verbose
              print "On post #{j}\r"
              j += 1
            end

            jsonl.puts(post.to_jsonl)
          end

          if @verbose
            print "\n"
            puts "Successfully wrote public room data\n\n"
          end
        end

        puts "Writing 1-on-1 room members..." if @verbose
        Hipchat.direct_channels.each do |members|
          puts members.inspect if @verbose
          jsonl.puts(%[{ "type": "direct_channel", "direct_channel": { "members": #{members.inspect} }}])
        end

        puts "Writing 1-on-1 room posts (oldest to newest)..." if @verbose
        Hipchat.direct_posts(jsonl, @verbose)
      end
    end

    def parse_rooms_arg
      @rooms = []
      @channels = []

      @data.each_slice(2).each do |hipchat_room, mattermost_room|
        if @verbose
          puts "Parsing rooms for Hipchat and Mattermost..."
          puts "Hipchat room is:               #{hipchat_room}"
          puts "Mattermost team & channel are: #{mattermost_room}"
        end

        team, room = mattermost_room.split(":")
        team       = Mattermost::Team.new(team)
        room       = Hipchat.rooms.find_by_name(hipchat_room)
        channel    = Mattermost::Channel.from_hipchat(room, team: team)

        room.team    = team
        room.channel = channel

        @rooms    << room
        @teams    << team
        @channels << channel

        puts "Successfully parsed rooms\n\n" if @verbose
      end

      @teams.uniq!
      @rooms.uniq!
      @channels.uniq!
    end
  end
end

