module Hipmost
  module Cmds
    class Private
      def initialize(path:, verbose: false)
        $path    = Pathname.new(path).expand_path
        @outpath = $path.join("..", "data.jsonl").expand_path
        @verbose = verbose
      end

      def run(args)
        subcommand = args.shift

        if ["list", "import"].include?(subcommand)
        else
          puts "Command invalid for room, must be import or list"
          exit 1
        end

        send(subcommand, args)
      end

      def list(_args)
        puts "Listing Private chats" if @verbose
        Hipchat.direct_channels.each do |members|
          puts members.inspect
        end

        true
      end

      def import(args)
        File.open(@outpath, "w") do |jsonl|
          puts "Writing version header..." if @verbose
          jsonl.puts %[{ "type": "version", "version": 1 }]

          puts "Writing room members..." if @verbose
          Hipchat.users.each do |_,user|
            jsonl.puts(user.to_jsonl)
          end

          puts "Writing 1-on-1 room members..." if @verbose
          Hipchat.direct_channels.each do |members|
            puts members.inspect if @verbose
            jsonl.puts(%[{ "type": "direct_channel", "direct_channel": { "members": #{members.inspect} }}])
          end

          puts "Writing 1-on-1 room posts (oldest to newest)..." if @verbose
          Hipchat.direct_posts(jsonl, @verbose)
        end

        true
      end
    end
  end
end
