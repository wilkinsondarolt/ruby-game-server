# frozen_string_literal: true

module GameServer
  # Base class for every game. Subclass it, declare settings with the class
  # DSL, override the hooks you need, and register it:
  #
  #   class Pong < GameServer::Game
  #     game_id :pong
  #     players min: 2, max: 2
  #     mode :realtime, tick_rate: 30
  #
  #     def on_start(players) = ...
  #     def on_action(player, action) = ...
  #     def tick(dt) = ...
  #     def state_for(player) = {...}
  #   end
  #
  #   GameServer.register(Pong)
  #
  # All hooks for one room run on the server's single reactor thread, so game
  # state never needs locking.
  class Game
    MODES = %i[turn realtime].freeze
    AUTO_START = %i[min max].freeze

    class << self
      def game_id(id = nil)
        id ? @game_id = id.to_s : @game_id
      end

      # The room starts once `auto_start` players have joined (see below), or
      # when a player sends `start_game` with at least `min` players present.
      def players(min:, max: min)
        raise ArgumentError, "min must be >= 1" if min < 1
        raise ArgumentError, "max must be >= min" if max < min

        @min_players = min
        @max_players = max
      end

      def mode(value = nil, tick_rate: 20)
        return setting(:@mode, :turn) unless value
        raise ArgumentError, "mode must be one of #{MODES.inspect}" unless MODES.include?(value)
        raise ArgumentError, "tick_rate must be positive" unless tick_rate.positive?

        @mode = value
        @tick_rate = tick_rate
      end

      # :max (default) starts when the room is full; :min starts as soon as
      # the minimum number of players is present.
      def auto_start(value = nil)
        return setting(:@auto_start, :max) unless value
        raise ArgumentError, "auto_start must be one of #{AUTO_START.inspect}" unless AUTO_START.include?(value)

        @auto_start = value
      end

      # Whether players may join a room after the game has started.
      def join_in_progress(value = nil)
        return setting(:@join_in_progress, false) if value.nil?

        @join_in_progress = value
      end

      def min_players = setting(:@min_players, 2)
      def max_players = setting(:@max_players, 2)
      def tick_rate = setting(:@tick_rate, 20)
      def realtime? = mode == :realtime

      def describe
        {
          id: game_id,
          min_players: min_players,
          max_players: max_players,
          mode: mode,
          tick_rate: (tick_rate if realtime?),
          join_in_progress: join_in_progress
        }.compact
      end

      private

      def setting(ivar, default)
        klass = self
        while klass <= Game
          return klass.instance_variable_get(ivar) if klass.instance_variable_defined?(ivar)

          klass = klass.superclass
        end
        default
      end
    end

    attr_reader :room

    def initialize(room)
      @room = room
    end

    # --- Hooks -------------------------------------------------------------

    # Called once when the game starts, with the players in join order.
    def on_start(players); end

    # Turn mode: called immediately for every `action` message.
    # Realtime mode: actions are buffered and delivered at the start of each
    # tick, in arrival order. Raise InvalidAction (or call `invalid!`) to
    # reject the action; only the sender is notified.
    def on_action(player, action); end

    # Realtime mode only. `dt` is the elapsed time in seconds.
    def tick(dt); end

    # Called when a player joins a game in progress (see `join_in_progress`).
    def on_player_join(player); end

    # Called after the player has been removed from `players`.
    def on_player_leave(_player)
      finish(reason: "not_enough_players") if players.size < self.class.min_players
    end

    # The state sent to `player` after every turn-mode action and every
    # realtime tick. Return only what that player is allowed to see.
    def state_for(_player)
      {}
    end

    # --- Helpers -----------------------------------------------------------

    def players
      room.players
    end

    # Sends an `event` message, e.g. broadcast(:coin_collected, by: player.id).
    def broadcast(name, data = {})
      room.broadcast("event", {name: name.to_s, data: data})
    end

    def send_to(player, name, data = {})
      player.send_message("event", {name: name.to_s, data: data})
    end

    # Ends the game. Everyone receives a final `state` and then `game_over`
    # with this result, and the room closes.
    def finish(**result)
      room.finish(result)
    end

    def finished?
      room.finished?
    end

    def invalid!(message)
      raise InvalidAction, message
    end
  end
end
