# frozen_string_literal: true

require "json"
require_relative "errors"

module GameServer
  # Newline-delimited JSON. Every message is one line:
  #
  #   {"type":"join_room","data":{"room_id":"abc123"}}\n
  #
  # Incoming data is parsed with symbolized keys.
  module Protocol
    Message = Data.define(:type, :data)

    module_function

    def encode(type, data = {})
      JSON.generate({type: type.to_s, data: data}) << "\n"
    end

    def decode(line)
      payload = JSON.parse(line, symbolize_names: true)
      raise ProtocolError, "message must be a JSON object" unless payload.is_a?(Hash)
      raise ProtocolError, "message must have a string \"type\"" unless payload[:type].is_a?(String)

      data = payload.fetch(:data, {}) || {}
      raise ProtocolError, "\"data\" must be a JSON object" unless data.is_a?(Hash)

      Message.new(type: payload[:type], data: data)
    rescue JSON::ParserError
      raise ProtocolError, "invalid JSON"
    end
  end
end
