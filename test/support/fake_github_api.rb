require "fileutils"

# Stub do cliente do GitHub para os testes: devolve JSON e um tarball local, sem rede.
# Fixture test/fixtures/repos/cabide.tar.gz: `git archive --prefix=deyvin-cabide-12a7f13/ HEAD` no ~/dev/labs/cabide,
# sem config/credentials.yml.enc (cifrado, fora do teste). Não tem .env nem segredo.
class FakeGithubApi
  TARBALL = Rails.root.join("test", "fixtures", "repos", "cabide.tar.gz").to_s
  COMMIT_SHA = "12a7f1358c4fa8f1513d5ea215db5f5c152debc7".freeze

  attr_reader :branches_requested

  def initialize(tarball: TARBALL, repository: {}, commit_sha: COMMIT_SHA)
    @tarball = tarball
    @repository = { "default_branch" => "main", "description" => "Cópia de teste do Cabide",
                    "topics" => [], "homepage" => nil }.merge(repository)
    @commit_sha = commit_sha
    @branches_requested = []
  end

  def repository(**)
    @repository
  end

  def commit_sha(branch:, **)
    @branches_requested << branch
    @commit_sha
  end

  def download_tarball(destination:, **)
    FileUtils.cp(@tarball, destination)
    destination
  end
end
