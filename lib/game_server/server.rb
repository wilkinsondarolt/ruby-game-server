# frozen_string_literal: true

require "socket"

module GameServer
  class Server
    attr_reader :host, :lobby

    # port: 0 picks a free port; read it back with #port after #start.
    def initialize(host: "127.0.0.1", port: 4000, games: GameServer.games, **connection_options)
      @host = host
      @port = port
      @lobby = Lobby.new(games: games)
      @dispatcher = Dispatcher.new(lobby: @lobby)
      @connection_options = connection_options
    end

    # Blocks until interrupted.
    def run
      Sync do |task|
        start(task)
        GameServer.logger.info("listening on #{host}:#{port} with games: #{lobby.games.keys.join(", ")}")
        @accept_task.wait
      ensure
        stop
      end
    end

    # Binds and starts accepting inside an existing reactor. Returns self.
    def start(parent = Async::Task.current)
      @tcp = TCPServer.new(host, @port)
      @lobby.task = parent
      @accept_task = parent.async { accept_loop }
      self
    end

    def port
      @tcp ? @tcp.local_address.ip_port : @port
    end

    def stop
      @lobby.shutdown
      @accept_task&.stop
      @tcp&.close unless @tcp&.closed?
    end

    private

    def accept_loop
      loop do
        socket = @tcp.accept
        Async::Task.current.async do
          Connection.new(socket, dispatcher: @dispatcher, **@connection_options).run
        end
      end
    end
  end
end
