require "set"

module Repo
  # Seleção determinística do que vai para o P1, sem LLM (§4.1).
  # Tokens são estimados por bytes / 3.5 (o OpenRouter não tem count_tokens, decisão 002).
  class Selector
    BUDGET_TOKENS = 120_000
    CHARS_PER_TOKEN = 3.5
    MAX_IMAGES = 12
    MIN_IMAGE_SIDE = 200
    IMAGE_EXTENSIONS = %w[png jpg jpeg webp].freeze

    # Ordem de prioridade do §4.1. Cada grupo é uma lista de globs relativos à raiz do repositório.
    TEXT_GROUPS = [
      %w[README*],
      %w[docs/**/*.md],
      %w[Gemfile package.json pyproject.toml go.mod Cargo.toml],
      [ "config/routes.rb", "app/**/page.*", "src/routes/**/*" ],
      [ "app/views/**/*", "src/pages/**/*" ],
      [ "tailwind.config.*", "**/application.css", "**/globals.css", "**/theme.*" ],
      %w[.env.example],
      %w[LICENSE*]
    ].freeze

    IMAGE_PATTERNS = [ "docs/**/*", "screenshots/**/*", "public/*.{png,jpg,jpeg,webp}", "app/assets/images/**/*" ].freeze

    Result = Data.define(:text_files, :images, :estimated_tokens)
    Image = Data.define(:path, :width, :height)

    def self.call(root, budget: BUDGET_TOKENS)
      new(root, budget: budget).call
    end

    def self.estimate_tokens(bytes)
      (bytes / CHARS_PER_TOKEN).ceil
    end

    def initialize(root, budget: BUDGET_TOKENS)
      @root = root.to_s
      @budget = budget
    end

    def call
      text_files, tokens = select_text
      Result.new(text_files: text_files, images: select_images, estimated_tokens: tokens)
    end

    private

    # Um arquivo entra na primeira vez que aparece, na ordem dos grupos. Se não couber no orçamento, pula e segue.
    def select_text
      seen = Set.new
      selected = []
      tokens = 0

      TEXT_GROUPS.each do |patterns|
        Files.candidates(@root, patterns).each do |rel|
          next unless seen.add?(rel)
          next unless Files.text?(@root, rel)

          cost = self.class.estimate_tokens(File.size(File.join(@root, rel)))
          next if tokens + cost > @budget

          selected << rel
          tokens += cost
        end
      end

      [ selected, tokens ]
    end

    def select_images
      images = []

      image_candidates.each do |rel|
        break if images.size >= MAX_IMAGES
        next unless IMAGE_EXTENSIONS.include?(File.extname(rel).delete_prefix(".").downcase)

        probe = Media::Probe.call(File.join(@root, rel))
        next if probe.width.nil? || [ probe.width, probe.height ].min < MIN_IMAGE_SIDE

        images << Image.new(path: rel, width: probe.width, height: probe.height)
      rescue Media::Probe::Error
        next
      end

      images
    end

    # Primeiro as imagens referenciadas no README (na ordem do documento), depois as pastas do §4.1.
    def image_candidates
      (readme_image_refs + Files.candidates(@root, IMAGE_PATTERNS)).uniq
    end

    def readme_image_refs
      readme = Files.candidates(@root, %w[README*]).first
      return [] unless readme

      text = File.binread(File.join(@root, readme)).force_encoding("UTF-8").scrub
      refs = text.scan(/!\[[^\]]*\]\(\s*<?([^)\s>]+)/).flatten +
             text.scan(/<img[^>]*\bsrc=["']([^"']+)["']/i).flatten

      refs.map { |ref| ref.delete_prefix("./") }
          .reject { |ref| ref.match?(%r{\A(?:[a-z][a-z0-9+.-]*:|/)}i) }
          .select { |ref| Files.file?(@root, ref) }
          .uniq
    end
  end
end
