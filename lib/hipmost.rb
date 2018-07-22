require 'pathname'
require "hipmost/version"
require "hipmost/hipchat"
require "hipmost/mattermost"

require "hipmost/cmds"

module Hipmost
  class CLI
    def self.run(command, args, options)
      case command.to_sym
      when :room, :rooms
        Hipmost::Cmds::Room.new(**options).run(args)
      when :direct, :private
        Hipmost::Direct.new(**options).run(args)
      else
        puts "Invalid command"
        exit 1
      end
    end

    def save
      puts "Writing 1-on-1 room members..." if @verbose
      Hipchat.direct_channels.each do |members|
        puts members.inspect if @verbose
        jsonl.puts(%[{ "type": "direct_channel", "direct_channel": { "members": #{members.inspect} }}])
      end

      puts "Writing 1-on-1 room posts (oldest to newest)..." if @verbose
      Hipchat.direct_posts(jsonl, @verbose)
    end
  end
end

