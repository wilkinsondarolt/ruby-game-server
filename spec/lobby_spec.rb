# frozen_string_literal: true

RSpec.describe GameServer::Lobby do
  let(:lobby) { described_class.new }

  it "creates and finds rooms" do
    room = lobby.create_room("tic_tac_toe")

    expect(lobby.find(room.id)).to be(room)
    expect(lobby.rooms("tic_tac_toe")).to eq([room])
    expect(lobby.rooms("arena")).to be_empty
  end

  it "raises for unknown games and rooms", :aggregate_failures do
    expect { lobby.create_room("chess") }.to raise_error(GameServer::Error) { expect(_1.code).to eq("unknown_game") }
    expect { lobby.find("nope") }.to raise_error(GameServer::Error) { expect(_1.code).to eq("room_not_found") }
  end

  it "quick-matches into an open room before creating a new one" do
    a, b, c = %w[a b c].map { GameServer::Testing.player(_1) }

    first = lobby.quick_match("tic_tac_toe").tap { _1.join(a) }
    expect(lobby.quick_match("tic_tac_toe")).to be(first)
    first.join(b)

    expect(lobby.quick_match("tic_tac_toe").tap { _1.join(c) }).not_to be(first)
  end

  it "forgets rooms once they empty or finish" do
    player = GameServer::Testing.player
    room = lobby.create_room("tic_tac_toe")
    room.join(player)
    room.leave(player)

    expect(lobby.rooms).to be_empty
  end
end
