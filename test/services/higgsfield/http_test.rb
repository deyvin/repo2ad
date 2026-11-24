require "test_helper"

# Download e upload só para https em host público (o QA testa SSRF). Sem rede: o DNS é falso.
class Higgsfield::HttpTest < ActiveSupport::TestCase
  class FakeResolver
    def initialize(table) = @table = table
    def getaddresses(host) = Array(@table[host])
  end

  setup do
    @http = Higgsfield::Http.new(resolver: FakeResolver.new(
      "localhost" => [ "127.0.0.1", "::1" ],
      "metadata.test" => [ "169.254.169.254" ],
      "intranet.test" => [ "10.0.0.5" ],
      "misto.test" => [ "34.120.1.2", "192.168.0.10" ],
      "cdn.test" => [ "34.120.1.2" ]
    ))
  end

  test "recusa http, IPs internos e nomes que resolvem para a rede interna" do
    {
      "http://cdn.test/x.png" => /só https/,
      "https://127.0.0.1/x.png" => /rede interna/,
      "https://169.254.169.254/latest/meta-data/" => /rede interna/,
      "https://localhost/x.png" => /rede interna/,
      "https://[::1]/x.png" => /rede interna/,
      "https://[::ffff:127.0.0.1]/x.png" => /rede interna/,
      "https://10.1.2.3/x.png" => /rede interna/,
      "https://metadata.test/x" => /rede interna/,
      "https://intranet.test/x" => /rede interna/,
      "https://misto.test/x" => /rede interna/,
      "ftp://cdn.test/x" => /só https/
    }.each do |url, message|
      error = assert_raises(Higgsfield::RequestError, url) { @http.get(url) }
      assert_match message, error.message, url
      assert_raises(Higgsfield::RequestError, url) { @http.put(url, "x", "image/png") }
    end
  end

  test "host público passa e a conexão vai para o IP verificado" do
    assert_equal "34.120.1.2", @http.send(:public_address, "cdn.test")
  end

  test "host que não resolve é erro transitório" do
    assert_raises(Higgsfield::TransientError) { @http.get("https://sumiu.test/x.png") }
  end
end
