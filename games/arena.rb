# frozen_string_literal: true

require_relative "../lib/game_server"

# Realtime reference game: everyone moves a dot around a field and races to
# collect coins. Starts as soon as one player joins; others can drop in.
#
# Action: {"dx": -1..1, "dy": -1..1}, the direction to move in. It persists
# until the next action, so clients only send it when input changes.
class Arena < GameServer::Game
  game_id :arena
  players min: 1, max: 8
  mode :realtime, tick_rate: 20
  auto_start :min
  join_in_progress true

  WIDTH = 800
  HEIGHT = 600
  SPEED = 200 # pixels per second
  PLAYER_RADIUS = 12
  COIN_RADIUS = 8
  WINNING_SCORE = 10

  attr_accessor :coin

  def initialize(room, rng: Random.new)
    super(room)
    @rng = rng
    @avatars = {}
  end

  def on_start(players)
    players.each { |player| spawn(player) }
    @coin = random_point
  end

  def on_player_join(player)
    spawn(player)
  end

  def on_player_leave(player)
    @avatars.delete(player.id)
    super
  end

  def on_action(player, action)
    dx = action[:dx]
    dy = action[:dy]
    invalid!("dx and dy must be numbers") unless dx.is_a?(Numeric) && dy.is_a?(Numeric)

    avatar = @avatars.fetch(player.id)
    avatar[:dx] = dx.clamp(-1, 1).to_f
    avatar[:dy] = dy.clamp(-1, 1).to_f
  end

  def tick(dt)
    @avatars.each_value do |avatar|
      move(avatar, dt)
      next unless touching_coin?(avatar)

      avatar[:score] += 1
      broadcast(:coin_collected, player_id: avatar[:id], score: avatar[:score])
      return finish(winner: avatar[:id], scores: scores) if avatar[:score] >= WINNING_SCORE

      @coin = random_point
    end
  end

  def state_for(player)
    {
      you: player.id,
      width: WIDTH,
      height: HEIGHT,
      coin: @coin,
      players: @avatars.values
    }
  end

  def avatar(player) = @avatars[player.id]

  private

  def spawn(player)
    @avatars[player.id] = {id: player.id, name: player.name, color: @avatars.size % 8, score: 0, dx: 0.0, dy: 0.0,
                           **random_point}
  end

  def move(avatar, dt)
    length = Math.hypot(avatar[:dx], avatar[:dy])
    return if length.zero?

    scale = SPEED * dt / [length, 1.0].max # diagonal moves aren't faster
    avatar[:x] = (avatar[:x] + avatar[:dx] * scale).clamp(PLAYER_RADIUS, WIDTH - PLAYER_RADIUS).round(2)
    avatar[:y] = (avatar[:y] + avatar[:dy] * scale).clamp(PLAYER_RADIUS, HEIGHT - PLAYER_RADIUS).round(2)
  end

  def touching_coin?(avatar)
    Math.hypot(avatar[:x] - @coin[:x], avatar[:y] - @coin[:y]) <= PLAYER_RADIUS + COIN_RADIUS
  end

  def random_point
    {x: @rng.rand(PLAYER_RADIUS..WIDTH - PLAYER_RADIUS).to_f, y: @rng.rand(PLAYER_RADIUS..HEIGHT - PLAYER_RADIUS).to_f}
  end

  def scores
    @avatars.values.to_h { |avatar| [avatar[:id], avatar[:score]] }
  end
end

GameServer.register(Arena)
