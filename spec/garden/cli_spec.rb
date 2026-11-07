# frozen_string_literal: true

require "stringio"
require_relative "support"

RSpec.describe Garden::CLI do
  include_context "garden sandbox"

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def garden(*args)
    described_class.new(args, out: out, err: err).run
  end

  it "adds a project" do
    path = make_git_repo("my-app")

    expect(garden("add", path)).to eq(0)
    expect(out.string).to include("Added my-app (#{path})")
  end

  it "adds a project under a custom name" do
    expect(garden("add", make_git_repo("my-app"), "--name", "app")).to eq(0)
    expect(out.string).to include("Added app")
  end

  it "says when a project is already registered" do
    path = make_git_repo("my-app")
    garden("add", path)

    expect(garden("add", path)).to eq(0)
    expect(out.string).to include("my-app is already registered")
  end

  it "reports errors without a stack trace" do
    expect(garden("add", File.join(sandbox, "missing"))).to eq(1)
    expect(err.string).to start_with("garden: No such directory")
  end

  it "reports unknown options" do
    expect(garden("add", "--bogus")).to eq(1)
    expect(err.string).to include("invalid option: --bogus")
  end

  it "runs setup" do
    expect(garden("setup")).to eq(0)
    expect(out.string).to include("Linked garden-review")
  end

  it "shows help" do
    expect(garden("help")).to eq(0)
    expect(out.string).to include("Usage: garden")
  end

  it "rejects unknown commands" do
    expect(garden("bogus")).to eq(1)
    expect(err.string).to include("unknown command 'bogus'")
  end
end
