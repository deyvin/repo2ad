module Costs
  # Estimativa de créditos antes de gerar (T13). Soma o custo dos steps do creative: com spec (P4), os steps reais;
  # antes do P4, os padrões de cada receita (decisão 004). Cada estimativa do gateway fica no cache do Rails por 10 min,
  # com a chave pelo modelo e pelos params. Não manda prompt nem mídia: o custo vem só dos params.
  class Estimator
    CACHE_TTL = 10.minutes
    NANO = "nano_banana_2_1".freeze
    KLING = "kling4_0".freeze

    Step = Data.define(:name, :model, :credits)
    Result = Data.define(:total, :steps)
    Entry = Data.define(:creative, :total, :steps)
    Selection = Data.define(:total, :creatives)

    def self.for(creative, gateway: Higgsfield::Gateway.current)
      new(creative, gateway).call
    end

    def self.for_selection(project, gateway: Higgsfield::Gateway.current)
      entries = project.creatives.where(selected: true).order(:code).map do |creative|
        result = new(creative, gateway).call
        Entry.new(creative: creative, total: result.total, steps: result.steps)
      end
      Selection.new(total: entries.sum(&:total).round(2), creatives: entries)
    end

    def initialize(creative, gateway)
      @creative = creative
      @gateway = gateway
    end

    def call
      steps = planned_steps.map { |name, model, params| estimate(name, model, params) }
      Result.new(total: steps.sum(&:credits).round(2), steps: steps)
    end

    private

    # [nome do step, modelo (nil = compose local, sem custo), params]
    def planned_steps
      spec_steps = @creative.spec.is_a?(Hash) ? Array(@creative.spec["steps"]) : []
      return spec_steps.map { |step| [ step["name"], step["model"], step["params"] ] } if spec_steps.any?

      default_steps
    end

    def default_steps
      aspect = @creative.aspect_ratio
      nano = { aspect_ratio: aspect, resolution: "2k", thinking_level: "high" }
      kling = { aspect_ratio: aspect, duration: @creative.duration || 10, resolution: "1080p", mode: "image-to-video" }

      case @creative.recipe
      when "nb_image" then [ [ "main", NANO, nano ] ]
      when "kling_reference", "kling_magic" then [ [ "start_frame", NANO, nano ], [ "main", KLING, kling ] ]
      when "kling_keyframes" then [ [ "start_frame", nil, {} ], [ "end_frame", NANO, nano ], [ "main", KLING, kling ] ]
      else raise ArgumentError, "receita desconhecida: #{@creative.recipe.inspect}"
      end
    end

    def estimate(name, model, params)
      return Step.new(name: name, model: nil, credits: 0.0) if model.nil?

      params = params.to_h.symbolize_keys.compact
      credits = Rails.cache.fetch(cache_key(model, params), expires_in: CACHE_TTL) do
        @gateway.cost(model: model, params: params)
      end
      Step.new(name: name, model: model, credits: credits.to_f)
    end

    def cache_key(model, params)
      "higgsfield-cost:#{model}:#{params.sort.to_h.to_json}"
    end
  end
end
