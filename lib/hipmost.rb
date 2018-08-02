require 'pathname'
require "hipmost/version"
require "hipmost/hipchat"
require "hipmost/mattermost"

require "hipmost/cmds"

module Hipmost
  class CLI
    def self.run(command, args, options)
      case command.to_sym
      when :public, :room, :rooms
        Hipmost::Cmds::Room.new(**options).run(args)
      when :direct, :private
        Hipmost::Cmds::Private.new(**options).run(args)
      else
        puts "Invalid command"
        exit 1
      end
    end

  end
end

