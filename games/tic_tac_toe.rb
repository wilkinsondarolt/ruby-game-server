# frozen_string_literal: true

require_relative "../lib/game_server"

# Turn-based reference game.
#
# Action: {"cell": 0..8}, with cells numbered left-to-right, top-to-bottom.
class TicTacToe < GameServer::Game
  game_id :tic_tac_toe
  players min: 2, max: 2
  mode :turn

  LINES = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6]
  ].freeze

  def on_start(players)
    @board = Array.new(9)
    @marks = {players[0].id => "X", players[1].id => "O"}
    @turn = players[0]
  end

  def on_action(player, action)
    invalid!("not your turn") unless player.equal?(@turn)

    cell = action[:cell]
    invalid!("cell must be an integer from 0 to 8") unless cell.is_a?(Integer) && cell.between?(0, 8)
    invalid!("cell #{cell} is taken") if @board[cell]

    mark = @marks[player.id]
    @board[cell] = mark
    broadcast(:moved, player_id: player.id, cell: cell, mark: mark)

    @turn = opponent_of(player)
    if LINES.any? { |line| line.all? { |i| @board[i] == mark } }
      @turn = nil
      finish(winner: player.id)
    elsif @board.all?
      @turn = nil
      finish(draw: true)
    end
  end

  def on_player_leave(_player)
    @turn = nil
    finish(winner: players.first&.id, reason: "opponent_left")
  end

  def state_for(player)
    {
      board: @board,
      marks: @marks,
      your_mark: @marks[player.id],
      turn: @turn&.id # nil once the game is over
    }
  end

  private

  def opponent_of(player)
    players.find { |p| !p.equal?(player) }
  end
end

GameServer.register(TicTacToe)
