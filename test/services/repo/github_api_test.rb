require "test_helper"
require "tmpdir"
require "net/http"

module Repo
  # Net::HTTP de mentira: a resposta vem de uma fila e cada requisição fica registrada. Sem rede.
  class FakeNetHttp
    attr_reader :requests

    def initialize(*responses)
      @responses = responses
      @requests = []
    end

    def request(req, &block)
      @requests << req
      response = @responses.shift
      block ? block.call(response) : response
    end
  end

  # Troca só a abertura da conexão: o resto do GithubApi (cabeçalhos, status, streaming) roda de verdade.
  class ScriptedGithubApi < GithubApi
    def initialize(http, token: nil)
      super(token: token)
      @http = http
    end

    private

    def connect(_uri)
      yield @http
    end
  end

  class GithubApiTest < ActiveSupport::TestCase
    setup do
      @dir = Dir.mktmpdir("github-api-test")
    end

    teardown do
      FileUtils.remove_entry(@dir)
    end

    test "repository devolve o JSON e manda o token no cabeçalho" do
      http = FakeNetHttp.new(ok_response('{"default_branch":"main"}'))

      data = ScriptedGithubApi.new(http, token: "segredo").repository(owner: "deyvin", name: "cabide")

      assert_equal "main", data["default_branch"]
      assert_equal "Bearer segredo", http.requests.first["Authorization"]
    end

    test "sem token não manda Authorization" do
      http = FakeNetHttp.new(ok_response('{"default_branch":"main"}'))

      ScriptedGithubApi.new(http, token: nil).repository(owner: "o", name: "r")

      assert_nil http.requests.first["Authorization"]
    end

    test "404 vira mensagem clara" do
      http = FakeNetHttp.new(response(Net::HTTPNotFound, "404", "{}"))

      error = assert_raises(Repo::Error) do
        ScriptedGithubApi.new(http).repository(owner: "o", name: "r")
      end

      assert_match "não encontrado", error.message
    end

    test "limite de requisições vira mensagem com GITHUB_TOKEN" do
      http = FakeNetHttp.new(response(Net::HTTPForbidden, "403", "{}", "x-ratelimit-remaining" => "0"))

      error = assert_raises(Repo::Error) do
        ScriptedGithubApi.new(http).repository(owner: "o", name: "r")
      end

      assert_match "GITHUB_TOKEN", error.message
    end

    test "commit_sha codifica o branch e lê o sha" do
      http = FakeNetHttp.new(ok_response('{"sha":"abc123"}'))

      sha = ScriptedGithubApi.new(http).commit_sha(owner: "o", name: "r", branch: "feature/x")

      assert_equal "abc123", sha
      assert_includes http.requests.first.path, "feature%2Fx"
    end

    test "download segue o redirect para o codeload sem mandar o token" do
      http = FakeNetHttp.new(redirect_response("https://codeload.github.com/o/r/legacy.tar.gz/abc"),
                             streamed_response([ "ab", "cd" ]))
      destination = File.join(@dir, "t.tar.gz")

      ScriptedGithubApi.new(http, token: "segredo").download_tarball(owner: "o", name: "r", sha: "abc",
                                                                     destination: destination, max_bytes: 100)

      assert_equal "abcd", File.binread(destination)
      assert_equal "Bearer segredo", http.requests[0]["Authorization"]
      assert_nil http.requests[1]["Authorization"]
    end

    test "redirect para host fora da lista é recusado" do
      http = FakeNetHttp.new(redirect_response("https://evil.example/x.tar.gz"))

      error = assert_raises(Repo::Error) do
        ScriptedGithubApi.new(http).download_tarball(owner: "o", name: "r", sha: "abc",
                                                     destination: File.join(@dir, "t.tar.gz"), max_bytes: 100)
      end

      assert_match "redirecionamento inesperado", error.message
    end

    test "download acima do limite é recusado pelo content-length" do
      http = FakeNetHttp.new(streamed_response([ "x" ], headers: { "content-length" => "500" }))

      error = assert_raises(Repo::Error) do
        ScriptedGithubApi.new(http).download_tarball(owner: "o", name: "r", sha: "abc",
                                                     destination: File.join(@dir, "t.tar.gz"), max_bytes: 100)
      end

      assert_match "limite", error.message
    end

    test "download acima do limite durante o stream é recusado" do
      http = FakeNetHttp.new(streamed_response([ "x" * 60, "x" * 60 ]))

      error = assert_raises(Repo::Error) do
        ScriptedGithubApi.new(http).download_tarball(owner: "o", name: "r", sha: "abc",
                                                     destination: File.join(@dir, "t.tar.gz"), max_bytes: 100)
      end

      assert_match "limite", error.message
    end

    private

    def response(klass, code, body, headers = {})
      res = klass.new("1.1", code, "teste")
      headers.each { |key, value| res[key] = value }
      res.define_singleton_method(:body) { body }
      res
    end

    def ok_response(body)
      response(Net::HTTPOK, "200", body)
    end

    def redirect_response(location)
      response(Net::HTTPFound, "302", "", "location" => location)
    end

    def streamed_response(chunks, headers: {})
      res = response(Net::HTTPOK, "200", "", headers)
      res.define_singleton_method(:read_body) { |&blk| chunks.each(&blk) }
      res
    end
  end
end
