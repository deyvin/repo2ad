require "test_helper"
require "tmpdir"
require "zlib"
require "rubygems/package"
require_relative "../../support/fake_github_api"

module Repo
  class FetcherTest < ActiveSupport::TestCase
    CABIDE_URL = "https://github.com/deyvin/cabide".freeze

    setup do
      @dir = Dir.mktmpdir("fetcher-test")
    end

    teardown do
      FileUtils.remove_entry(@dir)
    end

    test "baixa o Cabide, tira a pasta raiz e devolve os metadados" do
      api = FakeGithubApi.new(repository: { "description" => "descrição", "topics" => [ "ai" ],
                                            "homepage" => "https://example.test" })

      result = Fetcher.call(CABIDE_URL, project_id: 7, api: api, base_dir: @dir)

      assert_equal [ "deyvin", "cabide", "main", FakeGithubApi::COMMIT_SHA ],
                   [ result.owner, result.name, result.branch, result.commit_sha ]
      assert_equal [ "ai" ], result.topics
      assert_equal "https://example.test", result.homepage
      assert_equal File.join(@dir, "7"), result.root
      assert File.file?(File.join(result.root, "README.md"))
      assert File.file?(File.join(result.root, "app/assets/tailwind/application.css"))
      refute File.exist?(File.join(result.root, "deyvin-cabide-12a7f13"))
    end

    test "usa o branch da URL quando existe" do
      api = FakeGithubApi.new

      Fetcher.call("#{CABIDE_URL}/tree/feature/x", project_id: 1, api: api, base_dir: @dir)

      assert_equal [ "feature/x" ], api.branches_requested
    end

    test "recusa download acima do limite" do
      error = assert_raises(Repo::Error) do
        Fetcher.call(CABIDE_URL, project_id: 2, api: FakeGithubApi.new, base_dir: @dir, max_download_bytes: 1000)
      end

      assert_match "limite", error.message
    end

    test "recusa tarball que não é gzip" do
      path = File.join(@dir, "lixo.tar.gz")
      File.write(path, "isto não é gzip")

      error = assert_raises(Repo::Error) do
        Fetcher.call(CABIDE_URL, project_id: 3, api: FakeGithubApi.new(tarball: path), base_dir: @dir)
      end

      assert_match "corrompido", error.message
    end

    test "recusa caminho com .. e não escreve fora da pasta" do
      path = build_tarball("evil.tar.gz") do |tar|
        tar.mkdir("root", 0o755)
        tar.add_file_simple("root/../escape.txt", 0o644, 3) { |io| io.write("bad") }
      end

      assert_raises(Repo::Error) do
        Fetcher.call(CABIDE_URL, project_id: 4, api: FakeGithubApi.new(tarball: path), base_dir: @dir)
      end
      refute File.exist?(File.join(@dir, "escape.txt"))
    end

    test "recusa caminho absoluto" do
      path = build_tarball("abs.tar.gz") do |tar|
        tar.add_file_simple("/abs-evil.txt", 0o644, 3) { |io| io.write("bad") }
      end

      assert_raises(Repo::Error) do
        Fetcher.call(CABIDE_URL, project_id: 5, api: FakeGithubApi.new(tarball: path), base_dir: @dir)
      end
    end

    test "ignora links simbólicos, inclusive o que aponta para fora e o que tenta escrever por eles" do
      outside = File.join(@dir, "outside")
      FileUtils.mkdir_p(outside)
      path = build_tarball("links.tar.gz") do |tar|
        tar.mkdir("root", 0o755)
        tar.add_file_simple("root/ok.txt", 0o644, 2) { |io| io.write("ok") }
        tar.add_symlink("root/link", File.join(@dir, "alvo.txt"), 0o777)
        tar.add_symlink("root/dirlink", outside, 0o777)
        tar.add_file_simple("root/dirlink/evil.txt", 0o644, 3) { |io| io.write("bad") }
      end

      result = Fetcher.call(CABIDE_URL, project_id: 6, api: FakeGithubApi.new(tarball: path), base_dir: @dir)

      assert_equal "ok", File.read(File.join(result.root, "ok.txt"))
      refute File.symlink?(File.join(result.root, "link"))
      refute File.exist?(File.join(result.root, "link"))
      refute File.exist?(File.join(outside, "evil.txt"))
    end

    test "recusa descompactado acima do limite" do
      path = build_tarball("grande.tar.gz") do |tar|
        tar.add_file_simple("root/a.txt", 0o644, 10) { |io| io.write("0123456789") }
      end

      assert_raises(Repo::Error) do
        Fetcher.call(CABIDE_URL, project_id: 8, api: FakeGithubApi.new(tarball: path), base_dir: @dir,
                                 max_extracted_bytes: 5)
      end
    end

    private

    def build_tarball(name)
      path = File.join(@dir, name)
      File.open(path, "wb") do |file|
        Zlib::GzipWriter.wrap(file) do |gzip|
          Gem::Package::TarWriter.new(gzip) { |tar| yield tar }
        end
      end
      path
    end
  end
end
