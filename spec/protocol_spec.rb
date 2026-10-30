# frozen_string_literal: true

RSpec.describe GameServer::Protocol do
  it "round-trips a message as one JSON line with symbol keys" do
    line = described_class.encode(:join_room, {room_id: "abc"})

    expect(line).to eq(%({"type":"join_room","data":{"room_id":"abc"}}\n))
    expect(described_class.decode(line)).to eq(described_class::Message.new(type: "join_room", data: {room_id: "abc"}))
  end

  it "defaults missing data to an empty hash" do
    expect(described_class.decode(%({"type":"ping"})).data).to eq({})
  end

  it "rejects malformed messages", :aggregate_failures do
    ["not json", "[1,2]", %({"data":{}}), %({"type":1}), %({"type":"x","data":[1]})].each do |line|
      expect { described_class.decode(line) }.to raise_error(GameServer::ProtocolError), line
    end
  end
end
