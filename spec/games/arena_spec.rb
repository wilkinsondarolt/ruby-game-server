# frozen_string_literal: true

RSpec.describe Arena do
  let(:room) { GameServer::Room.new(described_class, autotick: false) }
  let(:alice) { GameServer::Testing.player("alice") }
  let(:bob) { GameServer::Testing.player("bob") }
  let(:game) { room.game }

  before { room.join(alice) }

  def place(player, x:, y:) = game.avatar(player).merge!(x: x.to_f, y: y.to_f)

  it "starts with a single player and lets others drop in" do
    expect(room).to be_playing

    room.join(bob)

    expect(bob.connection.last("state").data[:state][:players].map { _1[:name] }).to eq(%w[alice bob])
  end

  it "applies buffered input on the next tick" do
    game.coin = {x: 790.0, y: 590.0}
    place(alice, x: 100, y: 100)

    room.handle_action(alice, {dx: 1, dy: 0})
    expect(game.avatar(alice)[:x]).to eq(100.0) # not applied until the tick

    room.step(0.5)

    expect(game.avatar(alice)).to include(x: 200.0, y: 100.0)
    expect(alice.connection.last("state").data[:tick]).to eq(1)
  end

  it "doesn't move faster diagonally and stays inside the field" do
    game.coin = {x: 790.0, y: 590.0}
    place(alice, x: 400, y: 300)
    room.handle_action(alice, {dx: 1, dy: 1})
    room.step(1.0)

    moved = Math.hypot(game.avatar(alice)[:x] - 400, game.avatar(alice)[:y] - 300)
    expect(moved).to be_within(0.1).of(Arena::SPEED)

    room.step(10.0)
    expect(game.avatar(alice)).to include(x: 800.0 - Arena::PLAYER_RADIUS, y: 600.0 - Arena::PLAYER_RADIUS)
  end

  it "rejects non-numeric input" do
    room.handle_action(alice, {dx: "left", dy: 0})
    room.step(0.05)

    expect(alice.connection.last("error").data[:message]).to eq("dx and dy must be numbers")
  end

  it "scores coins and ends the game at the winning score" do
    (Arena::WINNING_SCORE - 1).times do
      game.coin = game.avatar(alice).slice(:x, :y)
      room.step(0.05)
    end
    expect(game.avatar(alice)[:score]).to eq(Arena::WINNING_SCORE - 1)
    expect(alice.connection.last("event").data).to include(name: "coin_collected")

    game.coin = game.avatar(alice).slice(:x, :y)
    room.step(0.05)

    expect(room).to be_finished
    expect(alice.connection.last("game_over").data[:result]).to eq(winner: alice.id,
                                                                    scores: {alice.id.to_sym => 10})
  end

  it "keeps running while anyone is left and closes when empty" do
    room.join(bob)
    room.leave(alice)
    expect(room).to be_playing

    room.leave(bob)
    expect(room).to be_finished
  end
end
