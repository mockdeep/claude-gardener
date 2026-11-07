# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::TestCommands do
  include_context "garden sandbox"

  def project_with(*files, test_commands: nil)
    path = File.join(sandbox, "p")
    files.each do |f|
      FileUtils.mkdir_p(File.dirname(File.join(path, f)))
      f.end_with?("/") ? FileUtils.mkdir_p(File.join(path, f)) : File.write(File.join(path, f), "")
    end
    FileUtils.mkdir_p(path)
    Garden::Registry::Project.new(name: "p", path: path, test_commands: test_commands)
  end

  it "uses the project's own setting when there is one" do
    expect(described_class.for(project_with("Gemfile", test_commands: ["bin/test"]))).to eq(["bin/test"])
  end

  it "uses an empty setting as 'no tests'" do
    expect(described_class.for(project_with("Gemfile", test_commands: []))).to eq([])
  end

  {
    %w[Gemfile spec/] => ["bundle exec rspec"],
    %w[Gemfile] => ["bundle exec rake test"],
    %w[package.json] => ["npm test"],
    %w[pyproject.toml] => ["pytest"],
    %w[Cargo.toml] => ["cargo test"],
    %w[go.mod] => ["go test ./..."],
    %w[README.md] => []
  }.each do |files, commands|
    it "guesses #{commands.inspect} from #{files.join(' and ')}" do
      expect(described_class.for(project_with(*files))).to eq(commands)
    end
  end
end
