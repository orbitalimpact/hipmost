require 'json'

module Hipmost
  class RoomRepository
    attr_accessor :rooms, :name_index
    extend Forwardable

    def_delegators :@rooms, :size, :[], :select


    def load_from(path)
      new(path).load
    end

    def initialize(path)
      @path  = Pathname.new(path).join("rooms.json")
      @rooms = {}
      @name_index = {}
    end

    def load(data = file_data)
      json = JSON.load(data)

      json.each do |room_obj|
        room = room_obj["Room"]
        @rooms[room["id"]] = Room.new(room)
        @name_index[room["name"]] = room["id"]
      end
    end

    def find_by_name(name)
      self[name_index[name]]
    end

    def file_data
      File.read(@path)
    end

    class Room
      def initialize(attrs)
        @id    = attrs["id"]
        @attrs = attrs
      end
      attr_reader :id, :attrs

      def method_missing(method)
        attrs[method.to_s]
      end
    end
  end
end
