# frozen_string_literal: true

module GameServer
  # Registry of open rooms and the entry point for matchmaking.
  class Lobby
    # Parent task for room tick loops; set by Server#start.
    attr_accessor :task
    attr_reader :games

    def initialize(games: GameServer.games)
      @games = games
      @rooms = {}
    end

    def game_list
      games.values.map(&:describe)
    end

    def create_room(game_id)
      game_class = fetch_game(game_id)
      id = SecureRandom.alphanumeric(6)
      id = SecureRandom.alphanumeric(6) while @rooms.key?(id)
      @rooms[id] = Room.new(game_class, id: id, lobby: self)
    end

    def find(room_id)
      @rooms.fetch(room_id.to_s) { raise Error.new("room_not_found", "no room with id #{room_id.inspect}") }
    end

    # Joins the oldest joinable room for the game, or creates a new one.
    def quick_match(game_id)
      game_class = fetch_game(game_id)
      @rooms.each_value.find { |room| room.game_class == game_class && room.joinable? } || create_room(game_id)
    end

    def rooms(game_id = nil)
      list = @rooms.values
      list = list.select { |room| room.game_class.game_id == game_id.to_s } if game_id
      list
    end

    def remove(room)
      @rooms.delete(room.id) if @rooms[room.id].equal?(room)
    end

    def shutdown
      @rooms.values.each { |room| room.finish(reason: "server_shutdown") }
      @rooms.clear
    end

    private

    def fetch_game(game_id)
      games.fetch(game_id.to_s) { raise Error.new("unknown_game", "no game called #{game_id.inspect}") }
    end
  end
end
