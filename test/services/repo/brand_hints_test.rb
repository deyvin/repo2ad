require "test_helper"
require "tmpdir"
require_relative "../../support/fake_github_api"

module Repo
  class BrandHintsTest < ActiveSupport::TestCase
    setup do
      @dir = Dir.mktmpdir("brand-test")
      @root = File.join(@dir, "repo")
      FileUtils.mkdir_p(@root)
    end

    teardown do
      FileUtils.remove_entry(@dir)
    end

    test "com o Cabide: variáveis CSS, cores do tema e Google Fonts" do
      root = Fetcher.call("https://github.com/deyvin/cabide", project_id: "brand",
                                                             api: FakeGithubApi.new, base_dir: @dir).root

      hints = BrandHints.call(root)

      assert_equal "#f3efe7", hints.css_variables["--color-paper"]
      assert_equal "#c8432b", hints.css_variables["--color-chalk"]
      assert_includes hints.css_variables["--font-display"], "Instrument Serif"
      assert_includes hints.colors, "#f3efe7"
      assert_includes hints.colors, "#c8432b"
      assert_includes hints.google_fonts, "Instrument Serif"
      assert_includes hints.google_fonts, "Inter Tight"
    end

    test "cores de 3 dígitos viram 6 e cores de 8 dígitos são ignoradas" do
      write "app/assets/tailwind/application.css", ":root { --color-x: #abc; --color-y: #11223344; }"

      hints = BrandHints.call(@root)

      assert_includes hints.colors, "#aabbcc"
      assert hints.colors.all? { |color| color.length == 7 }
    end

    test "Google Fonts: famílias de um link com pesos e &amp; escapado" do
      write "app/views/layouts/application.html.erb",
            '<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&amp;family=JetBrains+Mono:wght@400&amp;display=swap" rel="stylesheet">'

      hints = BrandHints.call(@root)

      assert_equal [ "Instrument Serif", "JetBrains Mono" ], hints.google_fonts
    end

    private

    def write(rel, content)
      path = File.join(@root, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
    end
  end
end
