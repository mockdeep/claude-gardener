# frozen_string_literal: true

require "webmock/rspec"
require "json"

# Load all lib files
Dir[File.join(__dir__, "../lib/**/*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  config.before(:each) do
    WebMock.disable_net_connect!
  end
end

def fixture_path(name)
  File.join(__dir__, "fixtures", name)
end

def load_fixture(name)
  File.read(fixture_path(name))
end

def stub_github_api(path, response:, method: :get, status: 200)
  stub_request(method, "https://api.github.com#{path}")
    .to_return(
      status: status,
      body: response.to_json,
      headers: { "Content-Type" => "application/json" }
    )
end
