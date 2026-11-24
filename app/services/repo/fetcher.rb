require "fileutils"
require "rubygems/package"
require "tempfile"
require "zlib"

module Repo
  # Busca um repositório público: metadados, SHA do branch e tarball, extraído em tmp/repos/<project_id>/.
  # O tarball é dado não confiável: caminhos com ".." ou absolutos falham, links simbólicos são ignorados,
  # há teto de arquivos, de profundidade e de tamanho, e qualquer falha apaga a pasta extraída.
  class Fetcher
    MAX_DOWNLOAD_BYTES = 50 * 1024 * 1024
    # Teto do descompactado, contra bomba de descompressão.
    MAX_EXTRACTED_BYTES = 200 * 1024 * 1024
    MAX_ENTRIES = 20_000
    MAX_DEPTH = 40

    Result = Data.define(:owner, :name, :branch, :commit_sha, :default_branch, :description, :topics, :homepage, :root)

    def self.call(url, project_id:, **options)
      new(url, project_id: project_id, **options).call
    end

    def initialize(url, project_id:, api: GithubApi.new, base_dir: Rails.root.join("tmp", "repos"),
                   max_download_bytes: MAX_DOWNLOAD_BYTES, max_extracted_bytes: MAX_EXTRACTED_BYTES,
                   max_entries: MAX_ENTRIES, max_depth: MAX_DEPTH)
      @url = url.is_a?(Url) ? url : Url.new(url)
      @api = api
      @root = File.join(base_dir.to_s, project_id.to_s)
      @max_download_bytes = max_download_bytes
      @max_extracted_bytes = max_extracted_bytes
      @max_entries = max_entries
      @max_depth = max_depth
    end

    def call
      repo = @api.repository(owner: @url.owner, name: @url.name)
      # full_name é o nome atual: um repositório renomeado responde pelo nome antigo, mas o canônico vale para tudo.
      owner, name = repo.fetch("full_name", "#{@url.owner}/#{@url.name}").split("/", 2)
      default_branch = repo.fetch("default_branch")
      branch = @url.branch || default_branch
      sha = @api.commit_sha(owner: owner, name: name, branch: branch)

      Tempfile.create([ "repo2ad-", ".tar.gz" ]) do |tarball|
        tarball.close
        @api.download_tarball(owner: owner, name: name, sha: sha, destination: tarball.path,
                              max_bytes: @max_download_bytes)
        check_download_size!(tarball.path)
        extract(tarball.path)
      end

      Result.new(owner: owner, name: name, branch: branch, commit_sha: sha, default_branch: default_branch,
                 description: repo["description"], topics: Array(repo["topics"]), homepage: repo["homepage"],
                 root: @root)
    end

    private

    def check_download_size!(path)
      return if File.size(path) <= @max_download_bytes

      raise Error, "repositório acima do limite de #{@max_download_bytes / 1024 / 1024} MB"
    end

    # Qualquer falha no meio da extração apaga a pasta inteira: nada fica pela metade no disco.
    def extract(tarball_path)
      FileUtils.rm_rf(@root)
      FileUtils.mkdir_p(@root)
      extract_entries(tarball_path)
    rescue StandardError
      FileUtils.rm_rf(@root)
      raise
    end

    def extract_entries(tarball_path)
      root = File.realpath(@root)
      total = 0
      entries = 0

      File.open(tarball_path, "rb") do |io|
        Zlib::GzipReader.wrap(io) do |gzip|
          Gem::Package::TarReader.new(gzip) do |tar|
            tar.each do |entry|
              entries += 1
              raise Error, "repositório com arquivos demais (limite de #{@max_entries})" if entries > @max_entries

              relative = relative_path(entry.full_name)
              next if relative.nil?
              raise Error, "repositório com pastas aninhadas demais (limite de #{@max_depth} níveis)" if relative.count("/") + 1 > @max_depth

              target = safe_target(root, relative)
              if entry.directory?
                FileUtils.mkdir_p(target)
              elsif entry.file?
                total += entry.header.size
                raise Error, "repositório descompactado acima do limite de #{@max_extracted_bytes / 1024 / 1024} MB" if total > @max_extracted_bytes

                write_file(entry, target)
              end
              # Links simbólicos, hardlinks e dispositivos são ignorados: nada deles é criado.
            end
          end
        end
      end
    rescue Zlib::Error, Gem::Package::TarInvalidError, EOFError, SystemCallError
      # SystemCallError: caminhos conflitantes (arquivo "a" e depois "a/b.txt", ou pasta "d" e depois arquivo "d").
      raise Error, "arquivo do repositório corrompido ou com caminhos conflitantes"
    end

    # Tira a pasta raiz do tarball (<owner>-<repo>-<sha>/) e rejeita caminhos perigosos.
    def relative_path(full_name)
      raise Error, "tarball com caminho absoluto" if full_name.start_with?("/") || full_name.include?("\0")

      parts = full_name.split("/").reject(&:empty?).drop(1)
      return nil if parts.empty?
      raise Error, "tarball com caminho fora do repositório" if parts.include?("..")

      parts.reject { |part| part == "." }.join("/")
    end

    def safe_target(root, relative)
      target = File.expand_path(relative, root)
      raise Error, "tarball com caminho fora do repositório" unless target.start_with?("#{root}/")

      target
    end

    def write_file(entry, target)
      FileUtils.mkdir_p(File.dirname(target))
      File.open(target, "wb") do |file|
        while (chunk = entry.read(64 * 1024))
          file.write(chunk)
        end
      end
    end
  end
end
