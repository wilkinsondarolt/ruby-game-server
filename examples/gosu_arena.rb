# frozen_string_literal: true

# Realtime arena client using Gosu. Needs the optional gem group:
#
#   bundle config set --local with examples && bundle install
#   bundle exec exe/game-server
#   bundle exec ruby examples/gosu_arena.rb alice    # open as many as you like
#
# Arrow keys or WASD to move. Collect 10 coins to win.

begin
  require "gosu"
rescue LoadError => e
  abort <<~MSG
    Couldn't load gosu: #{e.message}

    Gosu builds against SDL2. See "Gosu demo setup" in the README:

      brew install sdl2                                  # macOS; on Linux: libsdl2-dev
      bundle config set --local build.gosu "--with-ldflags='-L/opt/homebrew/lib -lSDL2 -framework Cocoa'"  # macOS
      bundle config set --local with examples && bundle install
      bundle exec ruby examples/gosu_arena.rb alice
  MSG
end
require_relative "../lib/game_server/client"

class ArenaWindow < Gosu::Window
  COLORS = [0xff_e6194b, 0xff_3cb44b, 0xff_4363d8, 0xff_f58231, 0xff_911eb4, 0xff_42d4f4, 0xff_f032e6,
            0xff_bfef45].map { Gosu::Color.new(_1) }.freeze

  def initialize(client)
    super(800, 600)
    self.caption = "Arena: #{client.name}"
    @client = client
    @font = Gosu::Font.new(18)
    @state = nil
    @banner = "Connecting..."
    @last_input = nil

    client.on("state") { |data| @state = data[:state] }
    client.on("game_started") { @banner = nil }
    client.on("game_over") do |data|
      winner = @state&.dig(:players)&.find { _1[:id] == data[:result][:winner] }
      @banner = "Game over: #{winner ? "#{winner[:name]} wins" : data[:result][:reason]}. Press Enter to play again."
    end
    client.on("disconnected") { @banner = "Disconnected from server." }
    client.quick_match(:arena)
  end

  def update
    @client.poll

    input = [axis(Gosu::KB_RIGHT, Gosu::KB_D) - axis(Gosu::KB_LEFT, Gosu::KB_A),
             axis(Gosu::KB_DOWN, Gosu::KB_S) - axis(Gosu::KB_UP, Gosu::KB_W)]
    return if input == @last_input || @client.room.nil?

    @client.send_action(dx: input[0], dy: input[1]) # only on change; the server keeps the last direction
    @last_input = input
  end

  def button_down(id)
    if id == Gosu::KB_ESCAPE
      close
    elsif id == Gosu::KB_RETURN && @client.room.nil? && @client.connected?
      @banner = nil
      @last_input = nil
      @client.quick_match(:arena)
    else
      super
    end
  end

  def draw
    Gosu.draw_rect(0, 0, width, height, Gosu::Color.new(0xff_1e1e24))
    if @state
      coin = @state[:coin]
      Gosu.draw_rect(coin[:x] - 8, coin[:y] - 8, 16, 16, Gosu::Color::YELLOW, 1)

      @state[:players].each_with_index do |player, i|
        color = COLORS[player[:color] % COLORS.size]
        Gosu.draw_rect(player[:x] - 12, player[:y] - 12, 24, 24, color, 2)
        Gosu.draw_rect(player[:x] - 14, player[:y] - 14, 28, 28, Gosu::Color::WHITE, 1) if player[:id] == @state[:you]
        @font.draw_text("#{player[:name]}: #{player[:score]}", 10, 10 + i * 20, 3, 1, 1, color)
      end
    end
    @font.draw_text(@banner, 10, height - 30, 3) if @banner
  end

  private

  def axis(*keys) = keys.any? { Gosu.button_down?(_1) } ? 1 : 0
end

client = GameServer::Client.new(
  host: ENV.fetch("GAME_SERVER_HOST", "127.0.0.1"),
  port: Integer(ENV.fetch("GAME_SERVER_PORT", "4000")),
  name: ARGV[0] || "player-#{rand(1000)}"
)
ArenaWindow.new(client).show
client.close
