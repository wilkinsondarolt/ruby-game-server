# frozen_string_literal: true

require_relative "lib/game_server/version"

Gem::Specification.new do |spec|
  spec.name = "game_server"
  spec.version = GameServer::VERSION
  spec.authors = ["Wilkinson Darolt"]
  spec.email = ["wilki.darolt@gmail.com"]
  spec.summary = "A generic, pluggable game server for turn-based and real-time Ruby games."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["lib/**/*.rb", "exe/*", "games/*.rb", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["game-server"]
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 2.20"
  spec.add_dependency "logger"
end
