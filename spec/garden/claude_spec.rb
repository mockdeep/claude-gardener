# frozen_string_literal: true

require_relative "support"

RSpec.describe Garden::Claude do
  # Records the command and returns a canned result.
  let(:shell) do
    Class.new do
      attr_reader :calls
      attr_accessor :response

      def run(*cmd, chdir: nil, stdin: nil, timeout: nil)
        (@calls ||= []) << { cmd: cmd, chdir: chdir, stdin: stdin, timeout: timeout }
        response
      end
    end.new
  end

  let(:schema) { { type: "object" } }

  def respond(out, success: true, err: "")
    status = instance_double(Process::Status, success?: success)
    shell.response = Garden::Shell::Result.new(out: out, err: err, status: status)
  end

  def run(**opts)
    described_class.new(shell: shell).structured(
      prompt: "Find things", dir: "/code", schema: schema, tools: %w[Read Bash], **opts
    )
  end

  it "returns the structured output" do
    respond({ "is_error" => false, "structured_output" => { "findings" => [] } }.to_json)

    expect(run).to eq("findings" => [])
  end

  it "passes the prompt on stdin and runs in the given folder" do
    respond({ "structured_output" => {} }.to_json)

    run(allowed_tools: ["Bash(npm audit)", "Bash(npm audit *)"], model: "opus")

    call = shell.calls.first
    cmd = call[:cmd]
    flag = ->(name) { cmd[cmd.index(name) + 1] }
    expect(call).to include(chdir: "/code", stdin: "Find things")
    expect(cmd).to start_with("claude", "-p")
    expect(flag["--tools"]).to eq("Read,Bash")
    expect(flag["--allowed-tools"]).to eq("Bash(npm audit),Bash(npm audit *)")
    expect(flag["--model"]).to eq("opus")
    expect(flag["--permission-mode"]).to eq("dontAsk")
    expect(flag["--json-schema"]).to eq(schema.to_json)
  end

  it "leaves out optional flags when not given" do
    respond({ "structured_output" => {} }.to_json)

    run

    expect(shell.calls.first[:cmd]).not_to include("--allowed-tools", "--model", "--resume")
    expect(shell.calls.first[:cmd]).to include("--no-session-persistence")
  end

  it "saves the session when asked, and returns its id" do
    respond({ "structured_output" => { "a" => 1 }, "session_id" => "abc" }.to_json)

    response = described_class.new(shell: shell).run(
      prompt: "Fix", dir: "/code", schema: schema, tools: ["Edit"], persist: true,
      permission_mode: "acceptEdits", timeout: 60
    )

    expect(response).to eq(Garden::Claude::Response.new(data: { "a" => 1 }, session_id: "abc"))
    call = shell.calls.first
    expect(call[:cmd]).not_to include("--no-session-persistence")
    expect(call[:cmd][call[:cmd].index("--permission-mode") + 1]).to eq("acceptEdits")
    expect(call[:timeout]).to eq(60)
  end

  it "resumes a session" do
    respond({ "structured_output" => {} }.to_json)

    described_class.new(shell: shell).run(prompt: "Again", dir: "/code", schema: schema, tools: [],
                                          resume: "abc")

    cmd = shell.calls.first[:cmd]
    expect(cmd[cmd.index("--resume") + 1]).to eq("abc")
    expect(cmd).not_to include("--no-session-persistence")
  end

  it "raises with Claude's message when it reports an error" do
    respond({ "is_error" => true, "result" => "Credit balance too low" }.to_json, success: false)

    expect { run }.to raise_error(Garden::Error, "Claude failed: Credit balance too low")
  end

  it "raises with stderr when the output isn't JSON" do
    respond("", success: false, err: "command not found")

    expect { run }.to raise_error(Garden::Error, "Claude failed: command not found")
  end

  it "raises when there's no structured output" do
    respond({ "is_error" => false, "result" => "Hi" }.to_json)

    expect { run }.to raise_error(Garden::Error, /structured output/)
  end
end
