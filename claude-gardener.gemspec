# frozen_string_literal: true

require_relative "lib/garden/version"

Gem::Specification.new do |spec|
  spec.name = "claude-gardener"
  spec.version = Garden::VERSION
  spec.authors = ["Robert Fletcher"]
  spec.summary = "Run Claude over your local projects to make small, reviewable fixes."
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/garden.rb", "lib/garden/**/*", "skills/**/*", "exe/*"]
  spec.bindir = "exe"
  spec.executables = ["garden"]
end
