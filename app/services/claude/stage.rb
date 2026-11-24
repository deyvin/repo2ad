require "base64"
require "erb"
require "json_schemer"

module Claude
  # Uma etapa de raciocínio (P1–P5): carrega o prompt (common.md + <etapa>.md.erb), o schema e o effort/max_tokens
  # da tabela §5.0, monta o conteúdo do usuário e valida SEMPRE a resposta contra o schema completo (decisão 003).
  # Resposta inválida volta ao modelo com a lista de erros, no máximo MAX_RETRIES vezes.
  #
  # Subclasses definem STAGE (ex.: "p1_brief") e #user_content; podem definir #extra_errors(data) e #template_locals.
  class Stage
    PROMPTS_DIR = Rails.root.join("app", "prompts")
    SETTINGS = {
      "p1_brief" => { effort: "high", max_tokens: 16_000, label: "P1 (brief do produto)" },
      "p2_angles" => { effort: "medium", max_tokens: 8_000, label: "P2 (ângulos)" },
      "p3_menu" => { effort: "high", max_tokens: 16_000, label: "P3 (cardápio)" },
      "p4_spec" => { effort: "high", max_tokens: 16_000, label: "P4 (prompt de geração)" },
      "p5_review" => { effort: "medium", max_tokens: 4_000, label: "P5 (revisão)" }
    }.freeze
    MAX_RETRIES = 2
    # Imagem enviada ao modelo: path como o repositório (ou o upload) a chama, dimensões e os bytes JPEG/PNG.
    Image = Data.define(:path, :width, :height, :media_type, :data)
    RETRY_INSTRUCTION = "Your previous answer did not pass validation against the JSON Schema. " \
                        "Fix every error below and answer again with the complete JSON object only.".freeze

    attr_reader :calls

    def initialize(client: Client.new)
      @client = client
      @calls = []
    end

    def stage = self.class::STAGE
    def settings = SETTINGS.fetch(stage)
    def effort = settings[:effort]
    def max_tokens = settings[:max_tokens]

    def system_prompt
      common = File.read(PROMPTS_DIR.join("common.md")).strip
      body = ERB.new(File.read(PROMPTS_DIR.join("#{stage}.md.erb")), trim_mode: "-").result_with_hash(template_locals).strip
      "#{common}\n\n#{body}"
    end

    def schema
      @schema ||= JSON.parse(File.read(PROMPTS_DIR.join("schemas", "#{stage}.json")))
    end

    # Executa a etapa e devolve o JSON validado (Hash).
    def call
      messages = [ { role: "user", content: user_content } ]
      errors = []

      (MAX_RETRIES + 1).times do |attempt|
        response = @client.create(system: system_blocks, messages: messages, schema: schema, effort: effort, max_tokens: max_tokens)
        @calls << { attempt: attempt + 1, model: response.model, usage: response.usage }
        Rails.logger.info("[repo2ad] #{stage} tentativa #{attempt + 1}: #{response.model} #{response.usage.to_json}")

        data, errors = parse_and_validate(response.text)
        return data if errors.empty?

        Rails.logger.warn("[repo2ad] #{stage} tentativa #{attempt + 1} fora do schema: #{errors.first(5).join(" | ").truncate(500)}")

        messages += [
          { role: "assistant", content: response.text.presence || "{}" },
          { role: "user", content: "#{RETRY_INSTRUCTION}\n#{errors.first(30).map { "- #{_1}" }.join("\n")}" }
        ]
      end

      raise InvalidResponse, "A etapa #{settings[:label]} devolveu uma resposta fora do formato esperado depois de " \
                             "#{MAX_RETRIES + 1} tentativas. Primeiro problema: #{errors.first}"
    end

    # Erros de schema (json_schemer) + regras extras da etapa.
    def validation_errors(data)
      schema_errors = JSONSchemer.schema(schema).validate(data).map do |error|
        pointer = error["data_pointer"].presence || "/"
        "#{pointer}: #{error["error"]}"
      end
      schema_errors + extra_errors(data)
    end

    private

    # System + blocos fixos da etapa (ex.: contrato da receita e exemplos no P4), todos cacheáveis (máx. 4).
    def system_blocks
      [ system_prompt, *fixed_blocks ].first(4).map { |text| { type: "text", text: text, cache_control: { type: "ephemeral" } } }
    end

    def fixed_blocks = []

    def parse_and_validate(text)
      data = JSON.parse(text.to_s)
      [ data, validation_errors(data) ]
    rescue JSON::ParserError => e
      [ nil, [ "the answer is not valid JSON (#{e.message.truncate(120)})" ] ]
    end

    def extra_errors(_data) = []
    def template_locals = {}

    # --- blocos do conteúdo do usuário ---------------------------------------------------------------

    def text_block(text) = { type: "text", text: text }

    # Conteúdo do repositório é dado não confiável (D4): vai sempre dentro de <repo_file>, e um
    # "</repo_file>" no meio do arquivo é neutralizado para não fechar a tag antes da hora.
    def repo_file_block(path, content)
      safe = content.to_s.gsub(%r{</(repo_file|repo_image|user_photo|repo_meta|brand_hints)}i, '<\\/\1')
      text_block(%(<repo_file path="#{attr(path)}">\n#{safe}\n</repo_file>))
    end

    # Imagem: marcador com path e dimensões, seguido do bloco base64.
    def image_blocks(tag, image)
      size = image.width && image.height ? %( width="#{image.width}" height="#{image.height}") : ""
      [
        text_block(%(<#{tag} path="#{attr(image.path)}"#{size}/>)),
        { type: "image", source: { type: "base64", media_type: image.media_type, data: Base64.strict_encode64(image.data) } }
      ]
    end

    def attr(value) = ERB::Util.html_escape(value.to_s)
  end
end
