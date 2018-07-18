require 'json'
require 'forwardable'
require_relative "room"

module Hipmost
  module Hipchat
    class RoomRepository
      attr_accessor :rooms, :name_index
      extend Forwardable

      def_delegators :@rooms, :size, :[], :select

      def self.load_from(path)
        new(path).tap(&:load)
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

    end
  end
end
