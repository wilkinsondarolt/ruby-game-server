# frozen_string_literal: true

module GameServer
  # Routes client messages to the lobby and rooms. Has no networking of its
  # own, so it can be tested with fake connections.
  class Dispatcher
    MAX_NAME_LENGTH = 32

    def initialize(lobby:)
      @lobby = lobby
    end

    def handle(player, message)
      type = message.type
      data = message.data

      unless player.identified? || %w[hello ping].include?(type)
        raise Error.new("not_identified", "send hello first")
      end

      case type
      when "hello" then hello(player, data)
      when "ping" then player.send_message("pong", data)
      when "list_games" then player.send_message("games", {games: @lobby.game_list})
      when "list_rooms"
        player.send_message("rooms", {rooms: @lobby.rooms(data[:game]).map(&:to_h)})
      when "create_room"
        ensure_not_in_room(player)
        @lobby.create_room(data[:game]).join(player)
      when "join_room" then @lobby.find(data[:room_id]).join(player)
      when "quick_match"
        ensure_not_in_room(player)
        @lobby.quick_match(data[:game]).join(player)
      when "leave_room" then current_room(player).leave(player)
      when "start_game" then current_room(player).request_start(player)
      when "action" then current_room(player).handle_action(player, data)
      else raise Error.new("unknown_type", "unknown message type #{type.inspect}")
      end
    rescue Error => e
      player.send_message("error", {code: e.code, message: e.message, in_reply_to: message.type})
    rescue StandardError => e
      GameServer.logger.error("error handling #{message.type}: #{e.class}: #{e.message}\n" \
                              "#{e.backtrace&.first(10)&.join("\n")}")
      player.send_message("error", {code: "internal_error", message: "internal server error"})
    end

    def disconnect(player)
      player.room&.leave(player)
    end

    private

    def hello(player, data)
      name = data[:name].to_s.strip[0, MAX_NAME_LENGTH]
      player.name = name.nil? || name.empty? ? "player-#{player.id[0, 4]}" : name
      player.send_message("welcome", {player_id: player.id, name: player.name})
    end

    def current_room(player)
      player.room || raise(Error.new("not_in_room", "you are not in a room"))
    end

    def ensure_not_in_room(player)
      raise Error.new("already_in_room", "leave your current room first") if player.room
    end
  end
end
