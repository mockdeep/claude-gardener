# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe ClaudeGardener::OutputWriter do
  let(:writer) { Class.new { include ClaudeGardener::OutputWriter }.new }

  describe "#write_output" do
    context "when GITHUB_OUTPUT is set" do
      it "writes single-line values as key=value" do
        Tempfile.create("github_output") do |f|
          allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(f.path)

          writer.write_output("skipped", "true")

          expect(File.read(f.path)).to eq("skipped=true\n")
        end
      end

      it "writes multi-line values with heredoc delimiter" do
        Tempfile.create("github_output") do |f|
          allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(f.path)

          writer.write_output("prompt", "line1\nline2")

          content = File.read(f.path)
          expect(content).to match(/\Aprompt<<EOF_\d+\nline1\nline2\nEOF_\d+\n\z/)
        end
      end

      it "appends to existing output" do
        Tempfile.create("github_output") do |f|
          allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(f.path)

          writer.write_output("first", "a")
          writer.write_output("second", "b")

          content = File.read(f.path)
          expect(content).to eq("first=a\nsecond=b\n")
        end
      end
    end

    context "when GITHUB_OUTPUT is not set" do
      it "prints to stdout" do
        allow(ENV).to receive(:fetch).with("GITHUB_OUTPUT", nil).and_return(nil)

        expect { writer.write_output("key", "value") }.to output("key=value\n").to_stdout
      end
    end
  end
end
