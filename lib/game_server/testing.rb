# frozen_string_literal: true

require_relative "../game_server"

module GameServer
  # Helpers for testing games without sockets:
  #
  #   alice = GameServer::Testing.player("alice")
  #   room  = GameServer::Room.new(MyGame, autotick: false)
  #   room.join(alice)
  #   room.handle_action(alice, {move: "left"})
  #   room.step(0.05)                      # realtime games only
  #   alice.connection.last("state").data  # what alice's client would receive
  module Testing
    # Records messages exactly as a client would decode them (round-tripped
    # through JSON, so keys are symbols and state must be serializable).
    class FakeConnection
      attr_reader :messages

      def initialize
        @messages = []
        @closed = false
      end

      def send_message(type, data = {})
        @messages << Protocol.decode(Protocol.encode(type, data)) unless @closed
      end

      def of_type(type) = @messages.select { |m| m.type == type.to_s }
      def last(type) = of_type(type).last
      def types = @messages.map(&:type)
      def clear = @messages.clear
      def close(**) = @closed = true
      def closed? = @closed
    end

    module_function

    def player(name = "player")
      Player.new(FakeConnection.new, name: name)
    end
  end
end
