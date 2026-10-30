# frozen_string_literal: true

RSpec.describe GameServer::Game do
  it "has sensible defaults" do
    game = Class.new(described_class) { game_id :blank }

    expect(game.describe).to eq(id: "blank", min_players: 2, max_players: 2, mode: :turn, join_in_progress: false)
    expect(game.auto_start).to eq(:max)
  end

  it "describes realtime settings" do
    expect(Arena.describe).to eq(id: "arena", min_players: 1, max_players: 8, mode: :realtime, tick_rate: 20,
                                 join_in_progress: true)
  end

  it "inherits settings from parent game classes" do
    parent = Class.new(described_class) do
      players min: 3, max: 6
      mode :realtime, tick_rate: 10
    end
    child = Class.new(parent) { game_id :child }

    expect([child.min_players, child.max_players, child.mode, child.tick_rate]).to eq([3, 6, :realtime, 10])
  end

  it "validates DSL arguments", :aggregate_failures do
    expect { Class.new(described_class) { players min: 0 } }.to raise_error(ArgumentError)
    expect { Class.new(described_class) { players min: 3, max: 2 } }.to raise_error(ArgumentError)
    expect { Class.new(described_class) { mode :lockstep } }.to raise_error(ArgumentError)
    expect { Class.new(described_class) { auto_start :never } }.to raise_error(ArgumentError)
  end

  it "registers games by id" do
    expect(GameServer.games).to include("tic_tac_toe" => TicTacToe, "arena" => Arena)
    expect { GameServer.register(Class.new(described_class)) }.to raise_error(ArgumentError, /no game_id/)
  end
end
