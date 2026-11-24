# Stands in for Higgsfield::Mcp::Session: records tool calls and answers
# with canned results keyed by tool name (a value or a callable).
class FakeMcpSession
  attr_reader :calls

  def initialize(responses = {}, connected = true)
    @responses = responses
    @connected = connected
    @calls = []
  end

  def connected? = @connected

  def call(tool, arguments = {})
    @calls << [ tool, arguments.deep_stringify_keys ]
    response = @responses.fetch(tool) { raise "unexpected MCP tool call: #{tool}" }
    response.respond_to?(:call) ? response.call(arguments) : response
  end

  def args_for(tool)
    @calls.select { it.first == tool }.map(&:last)
  end
end

module SingletonStub
  # Temporarily replaces a singleton method (minitest 6 ships without minitest/mock).
  def stub_singleton(object, method_name, value)
    original = object.method(method_name)
    object.define_singleton_method(method_name) { |*| value.is_a?(Proc) ? value.call : value }
    yield
  ensure
    object.define_singleton_method(method_name, original)
  end
end
