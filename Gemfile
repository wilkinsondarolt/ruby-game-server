# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake", "~> 13.0"
gem "rspec", "~> 3.13"

# Only needed for examples/gosu_arena.rb (requires SDL2 system libraries).
# Enable with: bundle config set --local with examples
group :examples, optional: true do
  gem "gosu", "~> 1.4"
end
