module Stages
  # P4, prompt de geração de um criativo (§5.5): transforma o item do cardápio no spec executável da receita.
  # Depois do system vão, como blocos fixos cacheáveis, o contrato da receita (app/prompts/recipes) e os
  # exemplos aprovados (app/prompts/examples, §12). Além do schema, valida as regras do §5.5 e da receita.
  class CreativeSpec < Claude::Stage
    STAGE = "p4_spec".freeze
    RECIPE_FILES = {
      "nb_image" => %w[nb_image],
      "kling_reference" => %w[kling_reference],
      "kling_magic" => %w[kling_reference kling_magic], # decisão 008: roda pelo pipeline da kling_reference
      "kling_keyframes" => %w[kling_keyframes]
    }.freeze
    EXAMPLES = %w[i1 v3 h1].freeze
    STEP_REF = /\Astep:(start_frame|end_frame|main)\z/

    def initialize(creative, client: Claude::Client.new)
      super(client: client)
      @creative = creative
      @project = creative.project
    end

    def item = @creative.concept.to_h

    def user_content
      blocks = [
        text_block("<brief>\n#{JSON.pretty_generate(@project.brief.to_h)}\n</brief>"),
        text_block("<angle>\n#{JSON.pretty_generate(angle)}\n</angle>"),
        text_block("<item>\n#{JSON.pretty_generate(item)}\n</item>"),
        text_block("<media>\n#{JSON.pretty_generate(media_inventory)}\n</media>")
      ]
      item_media.each do |media|
        image = Claude::Stage::Image.new(path: media.path, width: media.width, height: media.height,
                                         media_type: media.file.content_type, data: media.file.download)
        blocks.concat(image_blocks(media.source == "upload" ? "user_photo" : "repo_image", image))
      end
      blocks << text_block("<user_instructions>\n#{@creative.instructions.presence || "(nenhuma)"}\n</user_instructions>")
      blocks
    end

    private

    def fixed_blocks
      recipe = RECIPE_FILES.fetch(@creative.recipe) { raise Claude::Error, "receita desconhecida: #{@creative.recipe}" }
      contract = recipe.map { |name| File.read(PROMPTS_DIR.join("recipes", "#{name}.md")).strip }.join("\n\n")
      examples = EXAMPLES.map { |name| File.read(PROMPTS_DIR.join("examples", "#{name}.md")).strip }.join("\n\n")
      [ "<recipe_contract>\n#{contract}\n</recipe_contract>", "<approved_examples>\n#{examples}\n</approved_examples>" ]
    end

    def angle
      angles = Array(@project.angles.to_h["angles"])
      angles.find { _1["key"] == item["angle_key"] } || angles.find { _1["primary"] } || {}
    end

    def project_media = @project.media_inputs.with_attached_file.select { _1.path.present? }.index_by(&:path)
    def item_media = Array(item["media_paths"]).filter_map { project_media[_1] }.select { _1.file.attached? }

    def media_inventory
      project_media.values.map do |media|
        { path: media.path, source: media.source, kind: media.kind, description: media.description,
          width: media.width, height: media.height }
      end
    end

    # §5.5 e contrato da receita (§6): o spec é executado direto pelo código.
    def extra_errors(data)
      return [] unless data.is_a?(Hash) && data["steps"].is_a?(Array)

      steps = data["steps"]
      errors = []
      errors << "/recipe: must be #{@creative.recipe.inspect} (the item's recipe)" if data["recipe"] != @creative.recipe
      errors.concat(recipe_shape_errors(steps))
      steps.each_with_index { |step, index| errors.concat(step_errors(step, index, steps)) if step.is_a?(Hash) }
      errors
    end

    def recipe_shape_errors(steps)
      expected = Recipes.for(@creative.recipe)::STEPS
      actual = steps.map { |step| [ step["name"], step["kind"] ] }
      return [] if expected.any? { |shape| shape == actual }

      [ "/steps: this recipe needs exactly #{expected.map { |shape| shape.map { _1.join(":") }.join(", ") }.join(" or ")} " \
        "(name:kind, in this order); got #{actual.map { _1.join(":") }.join(", ")}" ]
    end

    def step_errors(step, index, steps)
      at = "/steps/#{index}"
      errors = []
      case step["kind"]
      when "compose"
        errors << "#{at}: compose needs model null, prompt null and a compose_plan" unless step["model"].nil? && step["prompt"].nil? && step["compose_plan"]
        errors.concat(compose_plan_errors(step, at))
      when "nano_banana"
        errors << "#{at}/model: nano_banana needs model \"nano_banana_2_1\"" unless step["model"] == "nano_banana_2_1"
        errors << "#{at}/prompt: nano_banana needs a prompt" if step["prompt"].blank?
      when "kling"
        errors << "#{at}/model: kling needs model \"kling4_0\"" unless step["model"] == "kling4_0"
        errors << "#{at}/prompt: kling needs a prompt" if step["prompt"].blank?
        errors << "#{at}/params/mode: kling needs mode \"image-to-video\"" unless step.dig("params", "mode") == "image-to-video"
        errors.concat(kling_errors(step, at, steps))
        errors.concat(product_reference_errors(step, at))
      end
      errors.concat(input_errors(step, at, steps.first(index)))
      errors.concat(final_step_errors(step, at)) if step["name"] == "main"
      errors
    end

    # §6.2: na kling_reference (e na kling_magic) o vídeo leva até 4 referências do produto limpo.
    def product_reference_errors(step, at)
      return [] unless @creative.recipe.in?(%w[kling_reference kling_magic])

      count = Array(step.dig("inputs", "image_references")).size
      max = Recipes::KlingReference::MAX_PRODUCT_REFERENCES
      count > max ? [ "#{at}/inputs/image_references: at most #{max} product references for this recipe (got #{count})" ] : []
    end

    def kling_errors(step, at, steps)
      start = step.dig("inputs", "start_image")
      return [ "#{at}/inputs/start_image: kling needs a start_image" ] if start.blank?

      aspect = aspect_of(start, steps)
      wanted = step.dig("params", "aspect_ratio")
      return [] if aspect.nil? || aspect == wanted

      [ "#{at}/inputs/start_image: start image is #{aspect} but params.aspect_ratio is #{wanted}; the first frame must already be in the target aspect ratio" ]
    end

    # step:<name> só pode apontar para um step anterior; caminho de mídia precisa existir no projeto.
    def input_errors(step, at, previous)
      inputs = step["inputs"].to_h
      refs = Array(inputs["image_references"]) + [ inputs["start_image"], inputs["end_image"] ].compact
      refs.filter_map do |ref|
        if (match = STEP_REF.match(ref))
          "#{at}/inputs: #{ref} must refer to an earlier step" unless previous.any? { _1["name"] == match[1] }
        elsif !project_media.key?(ref)
          "#{at}/inputs: media #{ref.inspect} does not exist (use a path from <media> or step:<name>)"
        end
      end
    end

    def compose_plan_errors(step, at)
      plan = step["compose_plan"]
      return [] unless plan.is_a?(Hash)

      errors = []
      if plan["canvas_aspect"] != step.dig("params", "aspect_ratio")
        errors << "#{at}/compose_plan/canvas_aspect: must equal params.aspect_ratio (#{step.dig("params", "aspect_ratio")})"
      end
      errors << "#{at}/compose_plan/background_hex: use #rrggbb" unless plan["background_hex"].to_s.match?(Frames::Composer::HEX)
      Array(plan["layers"]).each_with_index do |layer, i|
        errors << "#{at}/compose_plan/layers/#{i}/media_path: #{layer["media_path"].inspect} does not exist" unless project_media.key?(layer["media_path"])
        errors << "#{at}/compose_plan/layers/#{i}/frame: phone is not supported yet; use browser, print or none" if layer["frame"] == "phone"
        errors << "#{at}/compose_plan/layers/#{i}/width_pct: must be > 0" unless layer["width_pct"].to_f.positive?
      end
      errors
    end

    def final_step_errors(step, at)
      errors = []
      aspect = step.dig("params", "aspect_ratio")
      errors << "#{at}/params/aspect_ratio: must be the item's #{item["aspect_ratio"]}" if item["aspect_ratio"] && aspect != item["aspect_ratio"]
      duration = item["duration_seconds"]
      if step["kind"] == "kling" && duration && step.dig("params", "duration") != duration
        errors << "#{at}/params/duration: must be the item's #{duration}"
      end
      errors
    end

    # Aspecto de um start_image: o do step referenciado (canvas do compose ou params) ou o da mídia real.
    def aspect_of(ref, steps)
      if (match = STEP_REF.match(ref))
        source = steps.find { _1["name"] == match[1] } or return nil
        source.dig("compose_plan", "canvas_aspect") || source.dig("params", "aspect_ratio")
      elsif (media = project_media[ref]) && media.width && media.height
        Media::Probe::ASPECTS.find { |_label, ratio| ((media.width.to_f / media.height - ratio) / ratio).abs <= Media::Probe::TOLERANCE }&.first
      end
    end
  end
end
