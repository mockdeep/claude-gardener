# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::Setup do
  include_context "garden sandbox"

  let(:target) { File.join(Garden::Paths.claude_skills_dir, "garden-review") }
  let(:source) { File.join(Garden::Paths.bundled_skills_dir, "garden-review") }

  it "links the review skill into Claude's skills folder" do
    expect(described_class.new.run).to eq([["garden-review", :linked]])
    expect(File.readlink(target)).to eq(source)
    expect(File).to exist(File.join(target, "SKILL.md"))
  end

  it "does nothing when the link is already there" do
    described_class.new.run

    expect(described_class.new.run).to eq([["garden-review", :already_linked]])
  end

  it "won't replace a link that points somewhere else" do
    FileUtils.mkdir_p(File.dirname(target))
    File.symlink("/somewhere/else", target)

    expect { described_class.new.run }.to raise_error(Garden::Error, /already links to/)
  end

  it "won't replace an existing folder" do
    FileUtils.mkdir_p(target)

    expect { described_class.new.run }.to raise_error(Garden::Error, /already exists/)
  end
end
