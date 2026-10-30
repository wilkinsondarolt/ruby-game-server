# frozen_string_literal: true

RSpec.describe TicTacToe do
  let(:room) { GameServer::Room.new(described_class) }
  let(:x) { GameServer::Testing.player("x") }
  let(:o) { GameServer::Testing.player("o") }

  before do
    room.join(x)
    room.join(o)
  end

  def play(player, cell) = room.handle_action(player, {cell: cell})
  def state(player) = player.connection.last("state").data[:state]

  it "starts when two players join, with X moving first" do
    expect(room).to be_playing
    expect(state(x)).to include(your_mark: "X", turn: x.id, board: Array.new(9))
    expect(state(o)).to include(your_mark: "O", turn: x.id)
  end

  it "alternates turns and shares the board" do
    play(x, 4)

    expect(state(o)).to include(turn: o.id, board: [nil, nil, nil, nil, "X", nil, nil, nil, nil])
    expect(o.connection.last("event").data).to eq(name: "moved", data: {player_id: x.id, cell: 4, mark: "X"})
  end

  it "rejects invalid moves for the sender only", :aggregate_failures do
    play(o, 0)
    expect(o.connection.last("error").data).to eq(code: "invalid_action", message: "not your turn")

    play(x, 9)
    expect(x.connection.last("error").data[:message]).to match(/0 to 8/)

    play(x, 0)
    play(o, 0)
    expect(o.connection.last("error").data[:message]).to eq("cell 0 is taken")

    expect(x.connection.of_type("error").size).to eq(1)
  end

  it "declares a winner on three in a row" do
    [[x, 0], [o, 3], [x, 1], [o, 4], [x, 2]].each { |player, cell| play(player, cell) }

    expect(room).to be_finished
    expect(o.connection.last("game_over").data[:result]).to eq(winner: x.id)
    expect(state(o)).to include(turn: nil)
    expect(state(o)[:board].first(3)).to eq(%w[X X X])
    expect(x.room).to be_nil
  end

  it "declares a draw on a full board" do
    [[x, 0], [o, 1], [x, 2], [o, 4], [x, 3], [o, 5], [x, 7], [o, 6], [x, 8]].each { |player, cell| play(player, cell) }

    expect(x.connection.last("game_over").data[:result]).to eq(draw: true)
  end

  it "awards the win to the remaining player when the opponent leaves" do
    room.leave(x)

    expect(o.connection.last("game_over").data[:result]).to eq(winner: o.id, reason: "opponent_left")
  end
end
