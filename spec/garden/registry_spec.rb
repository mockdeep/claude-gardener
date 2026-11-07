# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::Registry do
  include_context "garden sandbox"

  subject(:registry) { described_class.new }

  it "starts empty when there's no projects file" do
    expect(registry.projects).to eq([])
  end

  it "adds a git repo using its folder name" do
    path = make_git_repo("my-app")

    status, project = registry.add(path)

    expect(status).to eq(:added)
    expect(project).to have_attributes(name: "my-app", path: path, fix_limit: 2)
    expect(described_class.new.projects).to eq([project])
  end

  it "registers the repo root when given a subfolder" do
    path = make_git_repo("my-app")
    FileUtils.mkdir_p(File.join(path, "lib"))

    _, project = registry.add(File.join(path, "lib"))

    expect(project.path).to eq(path)
  end

  it "uses a custom name when given one" do
    _, project = registry.add(make_git_repo("my-app"), name: "app")

    expect(project.name).to eq("app")
  end

  it "doesn't add the same repo twice" do
    path = make_git_repo("my-app")
    registry.add(path)

    status, = registry.add(path)

    expect(status).to eq(:exists)
    expect(registry.projects.size).to eq(1)
  end

  it "rejects a name that's already taken" do
    registry.add(make_git_repo("my-app"))
    other = make_git_repo("other")

    expect { registry.add(other, name: "my-app") }
      .to raise_error(Garden::Error, /already registered/)
  end

  it "rejects a folder that isn't a git repo" do
    path = File.join(sandbox, "plain")
    FileUtils.mkdir_p(path)

    expect { registry.add(path) }.to raise_error(Garden::Error, /Not a git repository/)
  end

  it "rejects a folder that doesn't exist" do
    expect { registry.add(File.join(sandbox, "missing")) }
      .to raise_error(Garden::Error, /No such directory/)
  end

  it "reads fix_limit from the file when set" do
    FileUtils.mkdir_p(File.dirname(Garden::Paths.projects_file))
    File.write(Garden::Paths.projects_file, <<~YAML)
      projects:
        - name: my-app
          path: /code/my-app
          fix_limit: 5
    YAML

    expect(registry.projects.first.fix_limit).to eq(5)
  end
end
