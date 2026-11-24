ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# Nenhum teste fala com a Higgsfield: o gateway padrão é um FakeGateway (sem rede, sem créditos reais).
module FakeHiggsfieldGateway
  def self.included(base)
    base.setup { Higgsfield::Gateway.current = Higgsfield::FakeGateway.new }
    base.teardown { Higgsfield::Gateway.current = nil }
  end
end

ActiveSupport::TestCase.include FakeHiggsfieldGateway
ActionDispatch::IntegrationTest.include FakeHiggsfieldGateway
