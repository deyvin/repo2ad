module Repo
  # Varredura de arquivos do repositório extraído, com as exclusões do §4.1.
  module Files
    EXCLUDED_DIRS = %w[node_modules vendor dist build].freeze
    EXCLUDED_FILES = %w[
      Gemfile.lock package-lock.json yarn.lock pnpm-lock.yaml bun.lockb Cargo.lock poetry.lock go.sum Pipfile.lock
      composer.lock
    ].freeze
    BINARY_EXTENSIONS = %w[png jpg jpeg gif webp ico pdf zip gz tgz tar woff woff2 ttf otf eot mp3 mp4 mov wav heic].freeze
    MAX_TEXT_BYTES = 200 * 1024

    module_function

    # Arquivos regulares que casam com algum padrão (relativo à raiz), ordenados, sem os excluídos.
    def candidates(root, patterns)
      patterns.flat_map { |pattern| matches(root, pattern) }
              .uniq
              .sort
              .select { |rel| file?(root, rel) }
    end

    # Padrão sem barra (README*, Gemfile, LICENSE*) vale só para a raiz e não diferencia maiúsculas:
    # readme.md, Readme.md e README.md casam. Padrão com pasta usa o glob normal.
    def matches(root, pattern)
      if pattern.include?("/")
        Dir.glob(pattern, base: root)
      else
        Dir.children(root).select { |name| File.fnmatch?(pattern, name, File::FNM_CASEFOLD) }
      end
    end

    def file?(root, rel)
      return false if rel.start_with?("/") || rel.split("/").include?("..")

      path = File.join(root, rel)
      File.file?(path) && !File.symlink?(path) && !excluded?(rel)
    end

    def excluded?(rel)
      parts = rel.split("/")
      parts[0...-1].any? { |dir| EXCLUDED_DIRS.include?(dir) || dir.start_with?(".") } ||
        EXCLUDED_FILES.include?(parts.last)
    end

    def text?(root, rel)
      path = File.join(root, rel)
      return false if BINARY_EXTENSIONS.include?(File.extname(rel).delete_prefix(".").downcase)
      return false if File.size(path) > MAX_TEXT_BYTES

      !File.binread(path, 8000).include?("\x00")
    end
  end
end
