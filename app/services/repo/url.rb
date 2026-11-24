module Repo
  # Lê a URL colada pelo usuário e devolve owner, name e, se houver, o branch. Só aceita o GitHub.
  class Url
    MESSAGE = "informe a URL pública de um repositório do GitHub, ex.: https://github.com/dono/repo".freeze

    HTTPS = %r{\Ahttps://(?:www\.)?github\.com/(?<owner>[^/\s]+)/(?<name>[^/\s]+?)(?:\.git)?(?:/tree/(?<branch>\S+?))?/*\z}
    SSH = %r{\Agit@github\.com:(?<owner>[^/\s]+)/(?<name>[^/\s]+?)(?:\.git)?\z}
    OWNER = /\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\z/
    NAME = /\A[A-Za-z0-9_.-]{1,100}\z/

    attr_reader :owner, :name, :branch

    def initialize(raw)
      text = raw.to_s.strip.sub(/[?#].*\z/, "")
      match = HTTPS.match(text) || SSH.match(text)
      raise Error, MESSAGE unless match

      @owner = match[:owner]
      @name = match[:name]
      @branch = match.names.include?("branch") ? match[:branch] : nil

      raise Error, "dono ou nome do repositório com caracteres não suportados" unless valid_parts?
    end

    def to_s
      "#{owner}/#{name}"
    end

    private

    def valid_parts?
      OWNER.match?(owner) && NAME.match?(name) && !%w[. ..].include?(name)
    end
  end
end
