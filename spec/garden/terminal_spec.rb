# frozen_string_literal: true

require "stringio"
require_relative "support"

RSpec.describe Garden::Terminal do
  let(:out) { StringIO.new }

  def terminal(input) = described_class.new(input: StringIO.new(input), out: out)

  let(:choices) { { "approve" => "a", "reject" => "r", "skip" => "s" } }

  describe "#choose" do
    it "takes the default on Enter" do
      expect(terminal("\n").choose("Decision?", choices, default: "reject")).to eq("reject")
      expect(out.string).to include("approve (a) / reject (r, default) / skip (s)")
    end

    it "accepts a letter or a full word" do
      expect(terminal("a\n").choose("Decision?", choices, default: "skip")).to eq("approve")
      expect(terminal("Reject\n").choose("Decision?", choices, default: "skip")).to eq("reject")
    end

    it "asks again after an unknown answer" do
      expect(terminal("x\ns\n").choose("Decision?", choices, default: "approve")).to eq("skip")
      expect(out.string).to include("Please answer with one of: approve, reject, skip")
    end

    it "skips at end of input" do
      expect(terminal("").choose("Decision?", choices, default: "approve")).to eq("skip")
    end
  end

  describe "#yes?" do
    it "takes the default on Enter, and reads y or n" do
      expect(terminal("\n").yes?("Next?")).to be(true)
      expect(terminal("n\n").yes?("Next?")).to be(false)
      expect(terminal("yes\n").yes?("Next?", default: false)).to be(true)
    end

    it "says no at end of input" do
      expect(terminal("").yes?("Next?")).to be(false)
    end
  end

  describe "#run" do
    it "returns whether the program succeeded" do
      expect(terminal("").run("true")).to be(true)
      expect(terminal("").run("false")).to be(false)
    end

    it "runs in the given folder" do
      Dir.mktmpdir do |dir|
        terminal("").run("sh", "-c", "touch ran", chdir: dir)

        expect(File).to exist(File.join(dir, "ran"))
      end
    end

    it "puts Ctrl-C handling back afterwards" do
      before = trap("INT", "DEFAULT")
      terminal("").run("true")

      expect(trap("INT", before)).to eq("DEFAULT")
    end

    it "raises from run! when the program fails" do
      expect { terminal("").run!("false") }.to raise_error(Garden::Error, /didn't finish successfully/)
    end
  end
end
