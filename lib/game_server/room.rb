# frozen_string_literal: true

module GameServer
  # One match of one game. Tracks its players, owns the game instance and, in
  # realtime mode, runs the fixed-rate tick loop.
  class Room
    attr_reader :id, :game_class, :players, :status, :game, :tick_count

    # `autotick: false` skips the tick loop so tests can drive realtime games
    # deterministically with #step.
    def initialize(game_class, id: SecureRandom.alphanumeric(6), lobby: nil, autotick: true)
      @game_class = game_class
      @id = id
      @lobby = lobby
      @autotick = autotick
      @players = []
      @status = :waiting
      @inputs = []
      @tick_count = 0
    end

    def waiting? = @status == :waiting
    def playing? = @status == :playing
    def finished? = @status == :finished
    def full? = @players.size >= game_class.max_players

    def joinable?
      return false if full?

      waiting? || (playing? && game_class.join_in_progress)
    end

    def join(player)
      raise Error.new("already_in_room", "leave your current room first") if player.room
      raise Error.new("room_closed", "this room has closed") if finished?
      raise Error.new("room_full", "this room is full") if full?
      raise Error.new("game_in_progress", "this game has already started") unless joinable?

      @players << player
      player.room = self
      player.send_message("room_joined", {room: to_h})
      broadcast("player_joined", {player: player.to_h}, except: player)

      if playing?
        guard { @game.on_player_join(player) }
        push_state(only: player) if playing?
      elsif @players.size >= auto_start_threshold
        start
      end
    end

    def leave(player)
      return unless @players.delete(player)

      player.room = nil
      player.send_message("left_room", {room_id: id})
      broadcast("player_left", {player: player.to_h})

      if playing?
        guard { @game.on_player_leave(player) }
        if playing? && @players.empty?
          finish(reason: "abandoned")
        elsif playing?
          push_state
        end
      elsif @players.empty?
        @lobby&.remove(self)
      end
    end

    # Manual start for games that otherwise wait for a full room.
    def request_start(_player)
      raise Error.new("already_started", "the game has already started") unless waiting?
      if @players.size < game_class.min_players
        raise Error.new("not_enough_players", "need at least #{game_class.min_players} players")
      end

      start
    end

    def handle_action(player, action)
      raise Error.new("game_not_started", "the game has not started yet") unless playing?

      if game_class.realtime?
        @inputs << [player, action]
      elsif guard(player) { @game.on_action(player, action) } && playing?
        push_state
      end
    end

    # Advances a realtime game by one tick. Called by the tick loop, or
    # directly from tests when `autotick: false`.
    def step(dt)
      inputs = @inputs
      @inputs = []
      inputs.each do |player, action|
        break unless playing?
        next unless @players.include?(player)

        guard(player) { @game.on_action(player, action) }
      end
      return unless playing?

      @tick_count += 1
      guard { @game.tick(dt) }
      push_state if playing?
    end

    def finish(result = {})
      return if finished?

      was_playing = playing?
      @status = :finished
      push_state if was_playing
      broadcast("game_over", {room_id: id, result: result})
      @players.each { |player| player.room = nil }
      @players = []
      @inputs = []
      @lobby&.remove(self)
      @tick_task.stop if @tick_task && !@tick_task.current?
    end

    def broadcast(type, data = {}, except: nil)
      @players.each do |player|
        player.send_message(type, data) unless player.equal?(except)
      end
    end

    def to_h
      {
        id: id,
        game: game_class.game_id,
        status: status,
        players: @players.map(&:to_h),
        min_players: game_class.min_players,
        max_players: game_class.max_players
      }
    end

    private

    def auto_start_threshold
      game_class.auto_start == :min ? game_class.min_players : game_class.max_players
    end

    def start
      @status = :playing
      @game = game_class.new(self)
      broadcast("game_started", {room: to_h})
      guard { @game.on_start(@players.dup) }
      return unless playing?

      push_state
      start_tick_loop if game_class.realtime? && @autotick
    end

    def push_state(only: nil)
      guard do
        (only ? [only] : @players).each do |player|
          player.send_message("state", {tick: @tick_count, state: @game.state_for(player)})
        end
      end
    end

    # Runs game code. Returns true on success. An InvalidAction is reported
    # to `player` only. Any other error ends this room's game but leaves the
    # rest of the server running.
    def guard(player = nil)
      yield
      true
    rescue InvalidAction => e
      player&.send_message("error", {code: e.code, message: e.message})
      false
    rescue StandardError => e
      GameServer.logger.error("room #{id} (#{game_class.game_id}) crashed: #{e.class}: #{e.message}\n" \
                              "#{e.backtrace&.first(10)&.join("\n")}")
      finish(reason: "game_error") unless finished?
      false
    end

    # The tick loop is a child of the server's root task rather than of the
    # connection that triggered the start, so it outlives that connection.
    def start_tick_loop
      parent = @lobby&.task || Async::Task.current
      @tick_task = parent.async { tick_loop }
    end

    def tick_loop
      interval = 1.0 / game_class.tick_rate
      last = Async::Clock.now
      next_at = last

      while playing?
        next_at += interval
        delay = next_at - Async::Clock.now
        if delay.positive?
          sleep(delay)
        else
          next_at = Async::Clock.now # fell behind; don't try to catch up in a burst
        end

        now = Async::Clock.now
        step(now - last)
        last = now
      end
    end
  end
end
