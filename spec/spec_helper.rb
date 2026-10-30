# frozen_string_literal: true

require "game_server"
require "game_server/testing"
require "game_server/client"
require_relative "../games/tic_tac_toe"
require_relative "../games/arena"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { require _1 }

GameServer.logger = Logger.new(nil)

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.example_status_persistence_file_path = ".rspec_status"
  config.order = :random

  # Runs the example inside an Async reactor.
  config.around(:each, :async) { |example| Sync { example.run } }
end
