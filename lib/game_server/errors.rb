# frozen_string_literal: true

module GameServer
  # Base error. The `code` is sent to clients in `error` messages.
  class Error < StandardError
    attr_reader :code

    def initialize(code, message = code.to_s.tr("_", " "))
      @code = code.to_s
      super(message)
    end
  end

  # Raised by games to reject a player's action. Only that player is told.
  class InvalidAction < Error
    def initialize(message = "invalid action")
      super("invalid_action", message)
    end
  end

  # Raised when a line on the wire is not a valid message envelope.
  class ProtocolError < Error
    def initialize(message = "malformed message")
      super("protocol_error", message)
    end
  end
end
