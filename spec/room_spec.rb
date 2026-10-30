# frozen_string_literal: true

RSpec.describe GameServer::Room do
  let(:party_game) do
    Class.new(GameServer::Game) do
      game_id :party
      players min: 2, max: 4

      def on_action(player, action)
        raise "boom" if action[:crash]

        invalid!("nope") if action[:bad]
        (@log ||= []) << [player.name, action[:n]]
      end

      def state_for(player) = {me: player.name, log: @log || []}
    end
  end
  let(:room) { described_class.new(party_game) }
  let(:players) { %w[a b c d e].map { GameServer::Testing.player(_1) } }

  it "tells the joiner and everyone else" do
    room.join(players[0])
    room.join(players[1])

    expect(players[1].connection.last("room_joined").data[:room]).to include(id: room.id, game: "party",
                                                                               status: "waiting")
    expect(players[0].connection.last("player_joined").data[:player]).to eq(players[1].to_h)
    expect(players[1].connection.of_type("player_joined")).to be_empty
  end

  it "auto-starts when full by default and rejects further joins" do
    players.first(3).each { room.join(_1) }
    expect(room).to be_waiting

    room.join(players[3])
    expect(room).to be_playing
    expect(players[0].connection.types).to include("game_started", "state")

    expect { room.join(players[4]) }.to raise_error(GameServer::Error) { expect(_1.code).to eq("room_full") }
  end

  it "can be started manually once the minimum is reached" do
    room.join(players[0])
    expect { room.request_start(players[0]) }.to raise_error(GameServer::Error, /at least 2/)

    room.join(players[1])
    room.request_start(players[0])

    expect(room).to be_playing
    expect { room.request_start(players[0]) }.to raise_error(GameServer::Error) { expect(_1.code).to eq("already_started") }
  end

  it "rejects actions before the game starts" do
    room.join(players[0])

    expect { room.handle_action(players[0], {}) }.to raise_error(GameServer::Error) do |error|
      expect(error.code).to eq("game_not_started")
    end
  end

  context "when playing" do
    before do
      players.first(2).each { room.join(_1) }
      room.request_start(players[0])
    end

    it "sends each player their own view of the state after turn-mode actions" do
      room.handle_action(players[1], {n: 1})

      expect(players[0].connection.last("state").data[:state]).to eq(me: "a", log: [["b", 1]])
      expect(players[1].connection.last("state").data[:state]).to eq(me: "b", log: [["b", 1]])
    end

    it "reports InvalidAction to the sender and keeps playing" do
      players[0].connection.clear
      room.handle_action(players[0], {bad: true})

      expect(players[0].connection.types).to eq(["error"])
      expect(room).to be_playing
    end

    it "ends the game, not the server, when game code crashes" do
      room.handle_action(players[0], {crash: true})

      expect(room).to be_finished
      expect(players[1].connection.last("game_over").data[:result]).to eq(reason: "game_error")
    end

    it "ends the game by default when too few players remain" do
      room.leave(players[0])

      expect(players[1].connection.last("game_over").data[:result]).to eq(reason: "not_enough_players")
      expect(players[1].room).to be_nil
    end

    it "rejects joins to a game in progress" do
      expect { room.join(players[2]) }.to raise_error(GameServer::Error) { expect(_1.code).to eq("game_in_progress") }
    end
  end

  describe "realtime tick loop", :async do
    let(:ticker) do
      Class.new(GameServer::Game) do
        game_id :ticker
        players min: 1, max: 1
        mode :realtime, tick_rate: 50

        def tick(_dt)
          finish(reason: "done") if room.tick_count >= 5
        end
      end
    end

    it "ticks at the configured rate until the game finishes" do
      player = GameServer::Testing.player
      room = described_class.new(ticker)
      started = Async::Clock.now

      room.join(player)
      sleep(0.01) until room.finished?

      expect(Async::Clock.now - started).to be_within(0.05).of(0.1)
      expect(player.connection.of_type("state").map { _1.data[:tick] }).to eq([0, 1, 2, 3, 4, 5])
    end
  end
end
