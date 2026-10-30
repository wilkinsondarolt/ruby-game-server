# frozen_string_literal: true

# Play tic-tac-toe in the terminal. Start the server, then run this in two
# terminals:
#
#   ruby examples/terminal_tic_tac_toe.rb alice
#   ruby examples/terminal_tic_tac_toe.rb bob
#
# Set GAME_SERVER_HOST / GAME_SERVER_PORT to connect elsewhere.

require_relative "../lib/game_server/client"

def render(board)
  cells = board.each_with_index.map { |mark, i| mark || i.to_s }
  cells.each_slice(3).map { |row| " #{row.join(" | ")}" }.join("\n---+---+---\n")
end

client = GameServer::Client.new(
  host: ENV.fetch("GAME_SERVER_HOST", "127.0.0.1"),
  port: Integer(ENV.fetch("GAME_SERVER_PORT", "4000")),
  name: ARGV[0] || "player"
)
client.wait_for("welcome")
client.quick_match(:tic_tac_toe)
puts "Waiting for an opponent..."

loop do
  message = client.next_message
  data = message.data

  case message.type
  when "game_started" then puts "Game on: #{data[:room][:players].map { _1[:name] }.join(" vs ")}"
  when "state"
    state = data[:state]
    puts "\n#{render(state[:board])}\n\n"
    next if state[:turn].nil? # game over; the result follows
    next puts("Waiting for opponent's move...") unless state[:turn] == client.player_id

    print "You are #{state[:your_mark]}. Your move (0-8): "
    input = $stdin.gets or break
    client.send_action(cell: Integer(input.strip, exception: false))
  when "error"
    puts "Error: #{data[:message]}"
    if data[:code] == "invalid_action"
      print "Try again (0-8): "
      input = $stdin.gets or break
      client.send_action(cell: Integer(input.strip, exception: false))
    end
  when "game_over"
    result = data[:result]
    puts(if result[:draw] then "It's a draw!"
         elsif result[:winner] == client.player_id then "You win!#{" (opponent left)" if result[:reason]}"
         else "You lose."
         end)
    break
  when "disconnected"
    puts "Disconnected from server."
    break
  end
end

client.close
