module Hipmost
  module Cmds
    class Users
      def initialize(path:, verbose: false)
        $path    = Pathname.new(path).expand_path
        @verbose = verbose
      end

      def run(args)
        @outpath = $path.join("..", "Users.jsonl").expand_path
        save
        true
      end

      def save
        puts "Opening #{@outpath} for writing..." if @verbose

        File.open(@outpath, "w") do |jsonl|
          puts "Writing version header..." if @verbose
          jsonl.puts %[{ "type": "version", "version": 1 }]

          Hipchat.users.each {|userId, user| jsonl.puts user.to_jsonl }
        end
      end
    end
  end
end
