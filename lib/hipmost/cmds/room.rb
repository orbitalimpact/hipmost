module Hipmost
  module Cmds
    class Room
      def initialize(path:, verbose: false)
        $path    = Pathname.new(path).expand_path
        @verbose = verbose
      end

      def run(args)
        subcommand = args.shift

        if subcommand == "import"
       	  filename = args[0].gsub('/', '-')
          @outpath = $path.join("..", "#{filename}.jsonl").expand_path
        end

        if ["list", "import"].include?(subcommand)
        else
          puts "Command invalid for `public`; must be `import` or `list`"
          exit 1
        end

        send(subcommand, args)
      end

      def list(_args)
        puts "Listing rooms..." if @verbose
        unless Hipchat.rooms.empty?
          Hipchat.rooms.each do |_,room|
            puts room.display_name
          end
        else
          puts "No rooms found"
        end

        true
      end

      def import(args)
        rooms      = args
        rooms_size = rooms.size

        if rooms_size.zero? || (rooms_size % 2).nonzero?
          puts "Need a pair of rooms to migrate"
          exit 1
        end

        @data = rooms

        parse_rooms_arg
        save
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
        end
      end

      def parse_rooms_arg
        @rooms    = []
        @channels = []
        @teams    = []

        @data.each_slice(2).each do |hipchat_room, mattermost_room|
          if @verbose
            puts "Parsing rooms for Hipchat and Mattermost..."
            puts "Hipchat room is:               #{hipchat_room}"
            puts "Mattermost team & channel are: #{mattermost_room}"
          end

          team, channel_name = mattermost_room.split(":")
          team               = Mattermost::Team.new(team)
          room               = Hipchat.rooms.find_by_name(hipchat_room)
          channel            = Mattermost::Channel.from_hipchat(room, name: channel_name, team: team)

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
end
