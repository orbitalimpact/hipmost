require 'json'
require 'forwardable'
require_relative 'post'

module Hipmost
  module Hipchat
    class PostRepository
      attr_accessor :posts, :name_index
      extend Forwardable

      def_delegators :@posts, :size, :[], :select, :each

      def self.for_room(room)
        new(room).tap(&:load)
      end

      def initialize(room)
        @room  = room
        @path  = $path.join("rooms", room.id.to_s, "history.json")
        @posts = []
      end

      def load(data = file_data)
        return if !File.exists?(@path)
        json = JSON.load(data)

        json.each do |post_obj|
          next if post_obj.key?("NotificationMessage")
          next if post_obj.key?("GuestAccessMessage")
          next if post_obj.key?("ArchiveRoomMessage")
          next if post_obj.key?("TopicRoomMessage")          
          post = post_obj["UserMessage"]
          @posts << Post.new(post, @room, @room.private?)
        end
      end

      def file_data
        return if !File.exists?(@path)
        File.read(@path)
      end
    end
  end
end
