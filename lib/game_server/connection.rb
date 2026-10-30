# frozen_string_literal: true

module GameServer
  # One client socket. A reader fiber parses lines and hands them to the
  # dispatcher. A writer fiber drains an outbound queue, so a slow client
  # never blocks a broadcast to everyone else.
  #
  # Anything may call #close. Teardown always happens in the connection's own
  # fiber (#run), so closing one connection mid-broadcast can't re-enter the
  # caller.
  class Connection
    attr_reader :player

    def initialize(socket, dispatcher:, idle_timeout: 300, max_line_bytes: 16_384, max_queue: 1_000)
      @socket = socket
      @dispatcher = dispatcher
      @idle_timeout = idle_timeout
      @max_line_bytes = max_line_bytes
      @max_queue = max_queue
      @outbox = Async::Queue.new
      @done = Async::Queue.new
      @closed = false
      @player = Player.new(self)
    end

    def run(task = Async::Task.current)
      peer = peer_name
      GameServer.logger.info("connected #{peer} as #{player.id}")

      reader = task.async do
        read_loop
      ensure
        @done.push(:reader)
      end
      writer = task.async do
        write_loop
      ensure
        @done.push(:writer)
      end

      reason = @done.pop
      @outbox.close unless @outbox.closed?
      flush(task, writer) if reason == :reader
    ensure
      @closed = true
      reader&.stop
      writer&.stop
      @socket.close unless @socket.closed?
      @dispatcher.disconnect(player)
      GameServer.logger.info("disconnected #{peer} (#{player.name || player.id})")
    end

    def send_message(type, data = {})
      return if @closed

      if @outbox.size >= @max_queue
        GameServer.logger.warn("dropping slow client #{player.name || player.id}")
        close(flush: false)
        return
      end

      @outbox.push(Protocol.encode(type, data))
    end

    # flush: true lets queued messages go out first (e.g. a final error).
    def close(flush: true)
      return if @closed

      @closed = true
      @outbox.close
      @done.push(:abort) unless flush
    end

    def closed? = @closed

    private

    def read_loop
      while (line = read_line)
        next if line.strip.empty?

        begin
          message = Protocol.decode(line)
        rescue ProtocolError => e
          send_message("error", {code: e.code, message: e.message})
          next
        end

        @dispatcher.handle(player, message)
      end
    rescue Async::TimeoutError
      send_message("error", {code: "idle_timeout", message: "no messages for #{@idle_timeout}s"})
      close
    rescue IOError, SystemCallError
      # Peer went away.
    end

    # Returns nil at EOF.
    def read_line
      line = Async::Task.current.with_timeout(@idle_timeout) { @socket.gets("\n", @max_line_bytes) }
      if line && !line.end_with?("\n") && line.bytesize >= @max_line_bytes
        send_message("error", {code: "line_too_long", message: "messages are limited to #{@max_line_bytes} bytes"})
        close
        return nil
      end
      line
    end

    def write_loop
      while (chunk = @outbox.pop)
        # Batch whatever else is already queued into one write.
        while (more = @outbox.pop(timeout: 0))
          chunk << more
        end
        @socket.write(chunk)
      end
    rescue IOError, SystemCallError
      # Peer went away.
    end

    def flush(task, writer)
      task.with_timeout(1) { writer.wait }
    rescue Async::TimeoutError
      # Give up on a peer that isn't reading.
    end

    def peer_name
      @socket.remote_address.inspect_sockaddr
    rescue StandardError
      "unknown"
    end
  end
end
