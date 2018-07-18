require "hipmost/version"

module Hipmost
  class CLI
    def self.run(args)
      binding.pry
      new(**args).run
    end

    def initialize(path:, rooms:)
      @path    = Pathname.new(path).expand_path
      @outpath = @path.join("..", "out").expand_path
      @rooms   = rooms
    end

    def run
      load_metadata

      parse_rooms

      save
    end

    def load_metadata
      @users = UserRepository.load_from(@path)
      @rooms = RoomRepository.load_from(@path)
    end
  end
end
