# frozen_string_literal: true

# Standalone client for game loops (Gosu, Ruby2D, terminal). Depends only on
# the standard library, so it doesn't need async:
#
#   require "game_server/client"
#
#   client = GameServer::Client.new(port: 4000, name: "alice")
#   client.on("state") { |data| @state = data[:state] }
#   client.quick_match("arena")
#
#   # in your update loop, never blocks:
#   client.poll
#   client.send_action(dx: 1, dy: 0)

require "socket"
require_relative "protocol"

module GameServer
  class Client
    class TimeoutError < StandardError; end

    attr_reader :player_id, :name, :room

    def initialize(host: "127.0.0.1", port: 4000, name: nil, connect_timeout: 5)
      @socket = Socket.tcp(host, port, connect_timeout: connect_timeout)
      @inbox = Thread::Queue.new
      @backlog = []
      @handlers = Hash.new { |hash, type| hash[type] = [] }
      @write_lock = Mutex.new
      @connected = true
      @reader = Thread.new { read_loop }
      hello(name) if name
    end

    def connected? = @connected

    # Registers a callback for a message type ("state", "event", ...). It
    # runs on the thread that calls #poll / #next_message / #wait_for.
    def on(type, &block)
      @handlers[type.to_s] << block
      self
    end

    # Returns every message received since the last call, without blocking,
    # and runs their callbacks. Call it once per frame.
    def poll
      messages = @backlog.shift(@backlog.size)
      while (message = @inbox.pop(timeout: 0))
        messages << message
      end
      messages.each { |message| dispatch(message) }
    end

    # Blocks for the next message. timeout: nil waits forever.
    def next_message(timeout: nil)
      message = @backlog.shift || @inbox.pop(timeout: timeout)
      raise TimeoutError, "no message within #{timeout}s" unless message

      dispatch(message)
    end

    # Blocks until a message of one of `types` arrives (and, if a block is
    # given, the block returns true for its data). Other messages are kept,
    # in order, for the next #poll.
    #
    #   client.wait_for("state") { |data| data[:state][:turn] == client.player_id }
    def wait_for(*types, timeout: 5, &filter)
      types = types.map(&:to_s)
      matches = ->(message) { types.include?(message.type) && (filter.nil? || filter.call(message.data)) }
      if (index = @backlog.index(&matches))
        return dispatch(@backlog.delete_at(index))
      end

      deadline = monotonic_now + timeout if timeout
      loop do
        remaining = deadline && (deadline - monotonic_now)
        raise TimeoutError, "timed out waiting for #{types.join(" or ")}" if remaining && remaining <= 0

        message = @inbox.pop(timeout: remaining)
        raise TimeoutError, "timed out waiting for #{types.join(" or ")}" unless message
        return dispatch(message) if matches.call(message)

        @backlog << message
      end
    end

    def send_message(type, data = {})
      line = Protocol.encode(type, data)
      @write_lock.synchronize { @socket.write(line) }
    end

    def hello(name)
      @name = name
      send_message("hello", {name: name})
    end

    def list_games = send_message("list_games")
    def list_rooms(game = nil) = send_message("list_rooms", game ? {game: game.to_s} : {})
    def create_room(game) = send_message("create_room", {game: game.to_s})
    def join_room(room_id) = send_message("join_room", {room_id: room_id})
    def quick_match(game) = send_message("quick_match", {game: game.to_s})
    def leave_room = send_message("leave_room")
    def start_game = send_message("start_game")
    def send_action(action = {}) = send_message("action", action)
    def ping = send_message("ping")

    def close
      @connected = false
      @socket.close unless @socket.closed?
      @reader.join(1)
    end

    private

    def read_loop
      while (line = @socket.gets)
        begin
          @inbox << Protocol.decode(line)
        rescue ProtocolError
          next
        end
      end
    rescue IOError, SystemCallError
      # Closed locally or by the server.
    ensure
      @connected = false
      @inbox << Protocol::Message.new(type: "disconnected", data: {})
    end

    def dispatch(message)
      case message.type
      when "welcome"
        @player_id = message.data[:player_id]
        @name = message.data[:name]
      when "room_joined" then @room = message.data[:room]
      when "left_room", "game_over" then @room = nil
      end
      @handlers[message.type].each { |handler| handler.call(message.data, message) }
      message
    end

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
