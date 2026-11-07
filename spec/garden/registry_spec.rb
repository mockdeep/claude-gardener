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

  it "rejects names that aren't safe to use in file names" do
    path = make_git_repo("my-app")

    expect { registry.add(path, name: "../evil") }.to raise_error(Garden::Error, /can only use/)
    expect { registry.add(path, name: ".hidden") }.to raise_error(Garden::Error, /can only use/)
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

  def write_projects(yaml)
    FileUtils.mkdir_p(File.dirname(Garden::Paths.projects_file))
    File.write(Garden::Paths.projects_file, yaml)
  end

  it "fills in defaults for settings that aren't set" do
    write_projects(<<~YAML)
      projects:
        - name: my-app
          path: /code/my-app
    YAML

    expect(registry.projects.first).to have_attributes(fix_limit: 2, model: nil, audit_commands: [])
  end

  it "reads per-project settings, which win over the defaults section" do
    write_projects(<<~YAML)
      defaults:
        model: opus
        fix_limit: 4
      projects:
        - name: my-app
          path: /code/my-app
          fix_limit: 5
          audit_commands: [composer audit]
        - name: other
          path: /code/other
          model: sonnet
    YAML

    my_app, other = registry.projects
    expect(my_app).to have_attributes(fix_limit: 5, model: "opus", audit_commands: ["composer audit"])
    expect(other).to have_attributes(fix_limit: 4, model: "sonnet")
  end

  it "keeps the defaults section when adding a project" do
    write_projects("defaults:\n  model: opus\nprojects: []\n")

    registry.add(make_git_repo("my-app"))

    expect(registry.projects.first.model).to eq("opus")
  end

  it "finds a project by name" do
    _, project = registry.add(make_git_repo("my-app"))

    expect(registry.find("my-app")).to eq(project)
    expect { registry.find("nope") }.to raise_error(Garden::Error, /No project named 'nope'/)
  end
end
