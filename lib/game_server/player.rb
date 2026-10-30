# frozen_string_literal: true

module GameServer
  class Player
    attr_reader :id, :connection
    attr_accessor :name, :room

    def initialize(connection, id: SecureRandom.uuid, name: nil)
      @connection = connection
      @id = id
      @name = name
    end

    # Players must say `hello` before doing anything else.
    def identified?
      !@name.nil?
    end

    def send_message(type, data = {})
      connection.send_message(type, data)
    end

    def to_h
      {id: id, name: name}
    end

    def to_json(...)
      to_h.to_json(...)
    end
  end
end
