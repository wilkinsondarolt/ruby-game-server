# frozen_string_literal: true

require "socket"

RSpec.describe GameServer::Server, :integration do
  it "plays a full game of tic-tac-toe between two real clients" do
    with_server do |connect|
      alice = connect.call("alice")
      bob = connect.call("bob")

      alice.quick_match(:tic_tac_toe)
      room_id = alice.wait_for("room_joined").data[:room][:id]
      bob.quick_match(:tic_tac_toe)
      expect(bob.wait_for("room_joined").data[:room][:id]).to eq(room_id)

      [[alice, 0], [bob, 3], [alice, 1], [bob, 4], [alice, 2]].each do |client, cell|
        client.wait_for("state") { |data| data[:state][:turn] == client.player_id }
        client.send_action(cell: cell)
      end

      result = bob.wait_for("game_over").data[:result]
      expect(result).to eq(winner: alice.player_id)
      expect(bob.room).to be_nil
    end
  end

  it "streams realtime state at about the tick rate" do
    with_server do |connect|
      client = connect.call("runner")
      client.quick_match(:arena)
      client.wait_for("state")
      client.send_action(dx: 1, dy: 0)

      sleep 0.5
      ticks = client.poll.select { _1.type == "state" }.map { _1.data[:tick] }

      expect(ticks.size).to be_within(3).of(10) # 20 Hz for 0.5s
      expect(ticks).to eq(ticks.sort)
    end
  end

  it "notifies others when a client disconnects" do
    with_server do |connect|
      alice = connect.call("alice")
      bob = connect.call("bob")
      alice.quick_match(:tic_tac_toe)
      alice.wait_for("room_joined")
      bob.quick_match(:tic_tac_toe)
      bob.wait_for("game_started")

      alice.close

      expect(bob.wait_for("game_over").data[:result]).to eq(winner: bob.player_id, reason: "opponent_left")
    end
  end

  it "speaks plain JSON lines over TCP and survives bad input" do
    with_server do |_connect, port|
      socket = TCPSocket.new("127.0.0.1", port)
      socket.write("this is not json\n")
      expect(JSON.parse(socket.gets)).to include("type" => "error", "data" => include("code" => "protocol_error"))

      socket.write(%({"type":"hello","data":{"name":"nc"}}\n{"type":"list_games"}\n))
      expect(JSON.parse(socket.gets)["type"]).to eq("welcome")
      expect(JSON.parse(socket.gets)["data"]["games"].map { _1["id"] }).to include("tic_tac_toe")
    ensure
      socket&.close
    end
  end

  it "drops connections that send oversized lines" do
    with_server(max_line_bytes: 64) do |_connect, port|
      socket = TCPSocket.new("127.0.0.1", port)
      socket.write("#{"x" * 200}\n")

      expect(JSON.parse(socket.gets)["data"]["code"]).to eq("line_too_long")
      expect(socket.read).to be_empty # server closed the connection
    ensure
      socket&.close
    end
  end

  it "disconnects idle clients" do
    with_server(idle_timeout: 0.2) do |connect|
      client = connect.call("sleepy")

      expect(client.wait_for("error").data[:code]).to eq("idle_timeout")
      expect(client.wait_for("disconnected")).to be_truthy
    end
  end
end
