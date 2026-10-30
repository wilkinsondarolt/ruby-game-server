# game_server

A generic game server for Ruby games. You write each game as a small class.
The server handles connections, the lobby, rooms, matchmaking and, for
real-time games, the tick loop.

- **Turn-based or real-time, per game.** Turn games react to each action.
  Real-time games run a fixed-rate simulation (e.g. 20 Hz) and stream state.
- **Plain protocol.** Newline-delimited JSON over TCP. You can debug it with
  `nc`, and any language can speak it.
- **No locking in game code.** Everything runs as fibers on one
  [async](https://github.com/socketry/async) reactor thread.
- **Dependency-free client** (`GameServer::Client`) for Gosu, Ruby2D or
  terminal games. It only needs the standard library.

## Quick start

```sh
bundle install
bundle exec exe/game-server            # loads every games/*.rb, listens on 127.0.0.1:4000
```

Then, in two other terminals:

```sh
ruby examples/terminal_tic_tac_toe.rb alice
ruby examples/terminal_tic_tac_toe.rb bob
```

Options: `--host 0.0.0.0` (allow LAN play), `--port`, `--games DIR`,
`--idle-timeout SECONDS`.

### Gosu demo setup

The real-time demo uses Gosu, which is in an optional gem group and builds
against SDL2.

```sh
brew install sdl2
# macOS only: tell Gosu's build what to link (see below)
bundle config set --local build.gosu "--with-ldflags='-L/opt/homebrew/lib -lSDL2 -framework Cocoa'"
bundle config set --local with examples && bundle install
bundle exec ruby examples/gosu_arena.rb alice   # open several
```

Why the macOS `build.gosu` line is needed:
- Homebrew's `sdl2` is now `sdl2-compat`, and its `sdl2-config` doesn't
  support the `--static-libs` flag that Gosu 1.4.6's build relies on.
- Without the setting, Gosu installs but links against nothing, and
  `require "gosu"` fails with `symbol not found ... _OBJC_CLASS_$_NSScreen`.
- The single quotes matter, because Bundler splits the setting on spaces.
- If Gosu was installed before you added the setting, rebuild it with
  `bundle pristine gosu`.

## Writing a game

```ruby
# games/coin_flip.rb
require_relative "../lib/game_server"

class CoinFlip < GameServer::Game
  game_id :coin_flip
  players min: 2, max: 2        # room auto-starts when full
  mode :turn                    # or: mode :realtime, tick_rate: 30
  # auto_start :min             # start as soon as `min` players are in
  # join_in_progress true       # allow joining after the start

  def on_start(players)
    @guesses = {}
  end

  def on_action(player, action)
    invalid!("pick heads or tails") unless %w[heads tails].include?(action[:guess])
    invalid!("already guessed") if @guesses.key?(player.id)

    @guesses[player.id] = action[:guess]
    return unless @guesses.size == 2

    side = %w[heads tails].sample
    broadcast(:flipped, side: side)
    winners = @guesses.select { |_, guess| guess == side }.keys
    finish(winners: winners, side: side)
  end

  # Called for every player after each action (turn mode) or tick (realtime).
  # Return only what this player may see. Here, opponents' guesses stay hidden.
  def state_for(player)
    {your_guess: @guesses[player.id], guessed: @guesses.keys}
  end
end

GameServer.register(CoinFlip)
```

| Hook | When |
|---|---|
| `on_start(players)` | Once, when the room starts. |
| `on_action(player, action)` | Turn mode: on each `action` message. Realtime: at the start of the next tick, in arrival order. |
| `tick(dt)` | Realtime only, `tick_rate` times per second. `dt` is in seconds. |
| `on_player_join(player)` | Someone joined mid-game (`join_in_progress true`). |
| `on_player_leave(player)` | After the player is removed. The default ends the game when fewer than `min` players remain. |
| `state_for(player)` | Builds that player's `state` message. Must be JSON-serializable. |

**Helpers**
- `players` lists the players in the room.
- `broadcast(name, data)` sends an event to everyone, and `send_to(player, name, data)` sends one to a single player.
- `finish(**result)` ends the game.
- `invalid!(message)` rejects the current action; only the sender is told.

Action data arrives with **symbol keys** (`action[:cell]`).

If a game raises anything other than `InvalidAction`, that room ends with
`reason: "game_error"`. The error is logged, and the rest of the server keeps
running.

The reference games are [games/tic_tac_toe.rb](games/tic_tac_toe.rb) (turn)
and [games/arena.rb](games/arena.rb) (realtime).

### Testing a game

You don't need sockets. `GameServer::Testing` gives you players whose
connection records every message exactly as a client would decode it.

```ruby
require "game_server/testing"

alice = GameServer::Testing.player("alice")
bob   = GameServer::Testing.player("bob")
room  = GameServer::Room.new(CoinFlip, autotick: false)  # autotick: false => drive ticks with room.step(dt)
room.join(alice)
room.join(bob)

room.handle_action(alice, {guess: "heads"})
alice.connection.last("state").data   # => {tick: 0, state: {your_guess: "heads", guessed: [...]}}
```

See [spec/games/](spec/games/) for complete examples.

## Using the client

```ruby
require "game_server/client"   # or require_relative "path/to/lib/game_server/client"

client = GameServer::Client.new(host: "127.0.0.1", port: 4000, name: "alice")
client.on("state") { |data| @state = data[:state] }
client.on("game_over") { |data| puts data[:result] }
client.quick_match(:arena)

# In your game loop (e.g. Gosu's #update). Never blocks:
client.poll
client.send_action(dx: 1, dy: 0)
```

- For scripts and tests, the blocking `next_message` and
  `wait_for(type) { |data| condition }` are handy. Messages that don't match
  are kept for the next `poll`.
- Other helpers: `list_games`, `list_rooms`, `create_room`, `join_room`,
  `leave_room`, `start_game`, `ping`, `player_id`, `room`, `connected?`,
  `close`.

## Protocol

Every message is one line of JSON: `{"type": "...", "data": {...}}\n`.
Clients must send `hello` before anything else.

| Client → server | data |
|---|---|
| `hello` | `name` |
| `ping` | anything (echoed in `pong`) |
| `list_games` | |
| `list_rooms` | optional `game` |
| `create_room` / `quick_match` | `game` |
| `join_room` | `room_id` |
| `start_game` | Starts early, once `min` players are in. |
| `leave_room` | |
| `action` | game-specific |

| Server → client | data |
|---|---|
| `welcome` | `player_id`, `name` |
| `games` / `rooms` | `games: [...]` / `rooms: [...]` |
| `room_joined` | `room` |
| `left_room` | `room_id` |
| `player_joined` / `player_left` | `player` |
| `game_started` | `room` |
| `state` | `tick`, `state` (from `state_for`) |
| `event` | `name`, `data` (from `broadcast` / `send_to`) |
| `game_over` | `room_id`, `result` (from `finish`). You're back in the lobby. |
| `pong` | |
| `error` | `code`, `message`, `in_reply_to` |

Try it by hand:

```sh
$ nc localhost 4000
{"type":"hello","data":{"name":"me"}}
{"type":"list_games"}
```

**Limits**
- Lines are capped at 16 KB.
- Clients that send nothing for `--idle-timeout` seconds are disconnected.
  Send `ping` to stay connected.
- Clients that fall more than 1000 messages behind are dropped.

## Development

```sh
bundle exec rspec
```

Not implemented yet:
- Accounts and auth
- Persistence
- Reconnecting to a game in progress
- A WebSocket transport
- Running multiple server processes

DragonRuby runs on mruby, so it can't load `GameServer::Client`. It could
still speak the protocol directly.
