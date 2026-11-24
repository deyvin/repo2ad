require "test_helper"
require "tmpdir"
require_relative "../../support/fake_github_api"
require_relative "../../support/media_fixtures"

module Repo
  class SelectorTest < ActiveSupport::TestCase
    include MediaFixtures

    setup do
      @dir = Dir.mktmpdir("selector-test")
      @root = File.join(@dir, "repo")
      FileUtils.mkdir_p(@root)
    end

    teardown do
      FileUtils.remove_entry(@dir)
    end

    test "com o Cabide seleciona README, docs/screenshots/*.png e application.css" do
      root = Fetcher.call("https://github.com/deyvin/cabide", project_id: "cabide",
                                                             api: FakeGithubApi.new, base_dir: @dir).root

      result = Selector.call(root)

      assert_includes result.text_files, "README.md"
      assert_includes result.text_files, "app/assets/tailwind/application.css"
      screenshots = result.images.map(&:path).select { |path| path.start_with?("docs/screenshots/") }
      assert_equal Dir.glob("docs/screenshots/*.png", base: root).sort, screenshots.sort
      assert_operator result.images.size, :<=, Selector::MAX_IMAGES
      assert_operator result.estimated_tokens, :<=, Selector::BUDGET_TOKENS
    end

    test "prioridade e exclusões: README, docs, manifesto, tema, .env.example e LICENSE" do
      write "README.md", "# x\n"
      write "docs/guia.md", "guia"
      write "docs/binario.md", "\x00\x01\x02 binário"
      write "Gemfile", "gem 'rails'"
      write "Gemfile.lock", "lock"
      write "node_modules/pkg/application.css", "x"
      write "app/assets/tailwind/application.css", "body {}"
      write "app/assets/stylesheets/application.css", "a" * (201 * 1024)
      write "app/views/layouts/application.html.erb", "<html>"
      write ".env.example", "HF_BACKEND=mcp\n"
      write "LICENSE", "MIT"

      result = Selector.call(@root)

      assert_equal [ "README.md", "docs/guia.md", "Gemfile", "app/views/layouts/application.html.erb",
                     "app/assets/tailwind/application.css", ".env.example", "LICENSE" ],
                   result.text_files
    end

    test "orçamento: pula o arquivo que não cabe e segue com os menores" do
      write "README.md", "a" * 1000
      write "docs/a.md", "b" * 1000
      write "docs/b.md", "c" * 100

      result = Selector.call(@root, budget: 400)

      assert_equal [ "README.md", "docs/b.md" ], result.text_files
      assert_equal 286 + 29, result.estimated_tokens
    end

    test "estimativa de tokens é bytes / 3,5 arredondado para cima" do
      assert_equal 286, Selector.estimate_tokens(1000)
      assert_equal 29, Selector.estimate_tokens(100)
    end

    test "imagens: ignora as menores que 200 px e respeita o limite de 12" do
      docs = File.join(@root, "docs")
      FileUtils.mkdir_p(docs)
      make_image(docs, "pequena.png", size: "100x100")
      make_image(docs, "grande.png", size: "300x200")
      13.times { |i| make_image(docs, format("img%02d.png", i), size: "400x300") }

      paths = Selector.call(@root).images.map(&:path)

      refute_includes paths, "docs/pequena.png"
      assert_includes paths, "docs/grande.png"
      assert_equal 12, paths.size
    end

    test "imagens citadas no README vêm primeiro; URLs e caminhos com .. ficam de fora" do
      FileUtils.mkdir_p(File.join(@root, "docs"))
      make_image(File.join(@root, "docs"), "b.png", size: "300x300")
      make_image(File.join(@root, "docs"), "c.png", size: "300x300")
      make_image(@root, "a.png", size: "300x300")
      write "README.md", "![x](docs/b.png)\n<img src=\"./a.png\">\n![y](https://img.example/x.png)\n![z](../../etc/x.png)\n"

      paths = Selector.call(@root).images.map(&:path)

      assert_equal [ "docs/b.png", "a.png", "docs/c.png" ], paths
    end

    private

    def write(rel, content)
      path = File.join(@root, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
    end
  end
end
