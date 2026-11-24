require "tmpdir"

module Stages
  # P5, revisão do criativo gerado (§5.6): confere o texto, os checks, o aspecto medido e os defeitos visíveis.
  # Imagem: o próprio arquivo. Vídeo: a contact sheet de 7 quadros com timestamp (Media::ContactSheet).
  class Review < Claude::Stage
    STAGE = "p5_review".freeze
    STEP_REF = /\Astep:/

    def initialize(creative, client: Claude::Client.new)
      super(client: client)
      @creative = creative
    end

    def call
      raise Claude::Error, "o criativo #{@creative.code} não tem resultado para revisar" unless @creative.result.attached?

      Dir.mktmpdir("review") do |dir|
        @dir = dir
        super
      end
    end

    def user_content
      blocks = [
        text_block("<spec>\n#{JSON.pretty_generate(spec_summary)}\n</spec>"),
        text_block("<measured>\n#{JSON.pretty_generate(measured)}\n</measured>")
      ]
      references.each { |media, image| blocks.concat(image_blocks(media.source == "upload" ? "user_photo" : "repo_image", image)) }
      result = result_image
      label = video? ? %(<result kind="contact_sheet" timestamps="#{@sheet.timestamps.join(", ")}"/>) : %(<result kind="image"/>)
      blocks << text_block(label)
      blocks << { type: "image", source: { type: "base64", media_type: result.media_type, data: Base64.strict_encode64(result.data) } }
      blocks
    end

    private

    def spec = @creative.spec.to_h

    def spec_summary
      { code: @creative.code, recipe: @creative.recipe, aspect_ratio: @creative.aspect_ratio,
        duration_seconds: @creative.duration, on_screen_copy: Array(spec["on_screen_copy"]), checks: Array(spec["checks"]) }
    end

    def video? = @creative.result.content_type.to_s.start_with?("video/")

    def result_path
      @result_path ||= File.join(@dir, "result#{File.extname(@creative.result.filename.to_s)}").tap do |path|
        File.binwrite(path, @creative.result.download)
      end
    end

    def probe = @probe ||= Media::Probe.call(result_path)

    def measured
      { width: probe.width, height: probe.height, duration_seconds: probe.duration && video? ? probe.duration.round(2) : nil,
        aspect: probe.aspect, expected_aspect: @creative.aspect_ratio }
    end

    def result_image
      if video?
        @sheet = Media::ContactSheet.call(result_path, output_path: File.join(@dir, "contact_sheet.jpg"))
        Claude::Stage::Image.from_file(@sheet.path, path: "result")
      else
        Claude::Stage::Image.from_file(result_path, path: "result")
      end
    end

    # Mídias reais que o spec usou (referências, quadros e camadas), sem os step:<nome>.
    def references
      paths = Array(spec["steps"]).flat_map do |step|
        inputs = step["inputs"].to_h
        Array(inputs["image_references"]) + [ inputs["start_image"], inputs["end_image"] ] +
          Array(step.dig("compose_plan", "layers")).map { _1["media_path"] }
      end
      paths = paths.compact.reject { _1.match?(STEP_REF) }.uniq
      media = @creative.project.media_inputs.with_attached_file.where(path: paths).index_by(&:path)
      paths.filter_map { media[_1] }.select { _1.file.attached? }.map do |input|
        file = File.join(@dir, "ref-#{input.id}#{File.extname(input.file.filename.to_s)}")
        File.binwrite(file, input.file.download)
        [ input, Claude::Stage::Image.from_file(file, path: input.path) ]
      end
    end

    def extra_errors(data)
      return [] unless data.is_a?(Hash) && data["verdict"] == "regenerate"

      data["fix_instructions"].to_s.strip.empty? ? [ "/fix_instructions: required (short, in English) when verdict is regenerate" ] : []
    end
  end
end
