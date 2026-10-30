# frozen_string_literal: true

RSpec.describe GameServer::Dispatcher do
  let(:dispatcher) { described_class.new(lobby: GameServer::Lobby.new) }
  let(:player) { GameServer::Player.new(GameServer::Testing::FakeConnection.new) }
  let(:inbox) { player.connection }

  def send_msg(type, data = {}, as: player)
    dispatcher.handle(as, GameServer::Protocol::Message.new(type: type, data: data))
  end

  it "requires hello first" do
    send_msg("list_games")

    expect(inbox.last("error").data).to include(code: "not_identified", in_reply_to: "list_games")
  end

  it "welcomes players and trims or defaults their names" do
    send_msg("hello", {name: "  #{"x" * 40}  "})
    expect(inbox.last("welcome").data).to eq(player_id: player.id, name: "x" * 32)

    send_msg("hello", {name: ""})
    expect(player.name).to start_with("player-")
  end

  context "when identified" do
    before { send_msg("hello", {name: "alice"}) }

    it "lists games and rooms" do
      send_msg("list_games")
      send_msg("create_room", {game: "tic_tac_toe"})
      send_msg("list_rooms", {game: "tic_tac_toe"})

      expect(inbox.last("games").data[:games].map { _1[:id] }).to include("tic_tac_toe", "arena")
      expect(inbox.last("rooms").data[:rooms].map { _1[:id] }).to eq([player.room.id])
    end

    it "joins rooms and routes actions" do
      bob = GameServer::Testing.player("bob")
      send_msg("create_room", {game: "tic_tac_toe"})
      send_msg("join_room", {room_id: player.room.id}, as: bob)
      send_msg("action", {cell: 4})

      expect(bob.connection.last("state").data[:state][:board][4]).to eq("X")
    end

    it "won't put a player in two rooms" do
      send_msg("create_room", {game: "tic_tac_toe"})
      send_msg("quick_match", {game: "arena"})

      expect(inbox.last("error").data[:code]).to eq("already_in_room")
    end

    it "reports errors without raising", :aggregate_failures do
      send_msg("action", {})
      expect(inbox.last("error").data[:code]).to eq("not_in_room")

      send_msg("dance")
      expect(inbox.last("error").data[:code]).to eq("unknown_type")
    end

    it "removes the player from their room on disconnect" do
      send_msg("create_room", {game: "tic_tac_toe"})
      room = player.room

      dispatcher.disconnect(player)

      expect(room.players).to be_empty
    end
  end
end
