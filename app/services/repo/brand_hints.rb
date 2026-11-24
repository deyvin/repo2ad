require "cgi"

module Repo
  # Tokens de marca para o P1 (§4.1): variáveis CSS --color-* e --font-*, cores hex dos temas
  # e famílias do Google Fonts nos <link> das páginas.
  class BrandHints
    THEME_PATTERNS = [ "tailwind.config.*", "**/*.css", "**/theme.*", "**/globals.css" ].freeze
    MARKUP_PATTERNS = [ "app/views/**/*.{erb,html}", "src/**/*.{html,tsx,jsx,vue}", "public/**/*.html", "index.html" ].freeze

    CSS_VARIABLE = /(--(?:color|font)-[\w-]+)\s*:\s*([^;{}]+?)\s*;/
    HEX = /#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b/
    GOOGLE_FONTS = %r{fonts\.googleapis\.com/css2?\?([^"'\s<>]+)}

    Result = Data.define(:css_variables, :colors, :google_fonts)

    def self.call(root)
      new(root).call
    end

    def initialize(root)
      @root = root.to_s
    end

    def call
      theme = files(THEME_PATTERNS)
      markup = files(MARKUP_PATTERNS)

      Result.new(css_variables: css_variables(theme), colors: colors(theme),
                 google_fonts: google_fonts(theme + markup))
    end

    private

    def files(patterns)
      Files.candidates(@root, patterns).select { |rel| Files.text?(@root, rel) }
    end

    def read(rel)
      File.binread(File.join(@root, rel)).force_encoding("UTF-8").scrub
    end

    def css_variables(theme)
      vars = {}
      theme.each do |rel|
        read(rel).scan(CSS_VARIABLE) { |name, value| vars[name] ||= value }
      end
      vars
    end

    def colors(theme)
      theme.flat_map { |rel| read(rel).scan(HEX).map { |hex| normalize(hex) } }.uniq
    end

    def google_fonts(files)
      files.flat_map { |rel| families(read(rel)) }.uniq
    end

    def families(text)
      text.scan(GOOGLE_FONTS).flatten.flat_map do |query|
        query.gsub("&amp;", "&").split("&").filter_map do |param|
          next unless param.start_with?("family=")

          CGI.unescape(param.delete_prefix("family=").split(":").first.to_s)
        end
      end
    end

    def normalize(hex)
      digits = hex.delete_prefix("#").downcase
      digits = digits.chars.map { |char| char * 2 }.join if digits.length == 3
      "##{digits}"
    end
  end
end
