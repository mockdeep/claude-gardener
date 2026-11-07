# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::Shell do
  it "captures output and passes stdin" do
    result = described_class.run("sh", "-c", "cat; echo err >&2", stdin: "hello")

    expect(result).to be_success
    expect(result.out).to eq("hello")
    expect(result.err).to eq("err\n")
  end

  it "runs in the given folder" do
    Dir.mktmpdir do |dir|
      expect(described_class.run("pwd", chdir: dir).out.strip).to eq(File.realpath(dir))
    end
  end

  it "stops commands that run too long" do
    started = Time.now

    expect { described_class.run("sleep", "10", timeout: 0.2) }
      .to raise_error(Garden::Error, /didn't finish within 0.2 seconds/)
    expect(Time.now - started).to be < 5
  end

  it "raises with the error output in run!" do
    expect { described_class.run!("sh", "-c", "echo nope >&2; exit 3") }
      .to raise_error(Garden::Error, /failed: nope/)
  end
end
