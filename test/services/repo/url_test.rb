require "test_helper"

module Repo
  class UrlTest < ActiveSupport::TestCase
    test "aceita https, com ou sem barra final, .git, www e query" do
      [
        "https://github.com/deyvin/cabide",
        "https://github.com/deyvin/cabide/",
        "https://github.com/deyvin/cabide.git",
        "https://www.github.com/deyvin/cabide",
        "  https://github.com/deyvin/cabide?tab=readme  "
      ].each do |raw|
        assert_equal [ "deyvin", "cabide", nil ], parts(raw), raw
      end
    end

    test "aceita /tree/<branch>, inclusive branch com barra" do
      assert_equal [ "deyvin", "cabide", "main" ], parts("https://github.com/deyvin/cabide/tree/main")
      assert_equal [ "deyvin", "cabide", "feature/x" ], parts("https://github.com/deyvin/cabide/tree/feature/x")
    end

    test "aceita git@github.com:o/r.git" do
      assert_equal [ "deyvin", "cabide", nil ], parts("git@github.com:deyvin/cabide.git")
      assert_equal [ "deyvin", "cabide", nil ], parts("git@github.com:deyvin/cabide")
    end

    test "o host não diferencia maiúsculas" do
      assert_equal [ "deyvin", "cabide", nil ], parts("https://GITHUB.com/deyvin/cabide")
      assert_equal [ "deyvin", "cabide", nil ], parts("git@GitHub.com:deyvin/cabide.git")
    end

    test "to_s devolve owner/name" do
      assert_equal "deyvin/cabide", Url.new("https://github.com/deyvin/cabide.git").to_s
    end

    test "recusa o resto com erro em português" do
      [
        "https://gitlab.com/deyvin/cabide",
        "http://github.com/deyvin/cabide",
        "https://github.com/deyvin",
        "https://github.com/deyvin/cabide/pull/3",
        "https://github.com/../cabide",
        "https://github.com/deyvin/..",
        "",
        "cabide"
      ].each do |raw|
        error = assert_raises(Repo::Error, raw) { Url.new(raw) }
        assert_predicate error.message, :present?, raw
      end
    end

    private

    def parts(raw)
      url = Url.new(raw)
      [ url.owner, url.name, url.branch ]
    end
  end
end
