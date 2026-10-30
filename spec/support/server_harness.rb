# frozen_string_literal: true

# Runs a real server on a free port in a background thread for the duration
# of a block, so specs can connect real Clients to it.
module ServerHarness
  def with_server(games: GameServer.games, **options)
    ready = Thread::Queue.new
    stop = Thread::Queue.new

    thread = Thread.new do
      Sync do |task|
        server = GameServer::Server.new(port: 0, games: games, **options).start(task)
        ready << server.port
        stop.pop # Thread::Queue#pop yields to the reactor while waiting
        server.stop
      end
    rescue Exception => e # rubocop:disable Lint/RescueException
      ready << e
    end

    port = ready.pop(timeout: 5)
    raise port if port.is_a?(Exception)
    raise "server did not start" unless port

    clients = []
    connect = lambda do |name|
      GameServer::Client.new(port: port, name: name).tap do |client|
        client.wait_for("welcome")
        clients << client
      end
    end

    yield connect, port
  ensure
    clients&.each(&:close)
    stop&.push(true)
    thread&.join(5)
  end
end

RSpec.configure { |config| config.include ServerHarness, :integration }
