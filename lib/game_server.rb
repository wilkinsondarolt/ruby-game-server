# frozen_string_literal: true

require "async"
require "async/queue"
require "logger"
require "securerandom"

require_relative "game_server/version"
require_relative "game_server/errors"
require_relative "game_server/protocol"
require_relative "game_server/player"
require_relative "game_server/game"
require_relative "game_server/room"
require_relative "game_server/lobby"
require_relative "game_server/dispatcher"
require_relative "game_server/connection"
require_relative "game_server/server"

module GameServer
  class << self
    attr_writer :logger

    def logger
      @logger ||= Logger.new($stdout, progname: "game_server")
    end

    # Registered game classes, keyed by game_id.
    def games
      @games ||= {}
    end

    def register(game_class)
      id = game_class.game_id or raise ArgumentError, "#{game_class} has no game_id"
      games[id] = game_class
    end
  end
end
