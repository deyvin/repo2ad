require "tmpdir"

module Recipes
  # Executa o spec do P4 de um criativo, um step por vez, na ordem (§3.5 RenderCreativeJob):
  # - compose: roda local (Frames::Composer) e já anexa a saída;
  # - nano_banana / kling: submete pelo gateway e para; o PollRenderStepJob acompanha e chama de novo.
  # step:<nome> vira o job_id do step anterior (sem baixar e subir de novo) ou, se ele foi um compose, o upload da saída.
  # Quando todos terminam, o resultado do step main vai para creative.result.
  class Base
    STEP_REF = /\Astep:(start_frame|end_frame|main)\z/
    ROLES = { "image_references" => "image_references", "start_image" => "start_image", "end_image" => "end_image" }.freeze

    def initialize(creative, gateway: Higgsfield::Gateway.current)
      @creative = creative
      @gateway = gateway
    end

    # Avança até o próximo step remoto. Devolve :submitted, :waiting, :done ou :failed.
    def advance!
      ensure_render_steps!
      loop do
        step = @creative.render_steps.order(:id).detect { _1.status != "done" }
        return finish! if step.nil?
        return :waiting if step.status.in?(%w[submitted running])
        return fail!(step) if step.status == "failed"

        if step.kind == "compose"
          compose!(step)
        else
          submit!(step)
          return step.status == "failed" ? fail!(step) : :submitted
        end
      end
    end

    private

    def spec_steps = Array(@creative.spec.to_h["steps"])
    def spec_for(step) = spec_steps.find { _1["name"] == step.name } || raise(Error, "step #{step.name} não está no spec")

    def ensure_render_steps!
      return if @creative.render_steps.exists?
      raise Error, "o criativo #{@creative.code} ainda não tem spec (P4)" if spec_steps.empty?

      spec_steps.each do |step|
        @creative.render_steps.create!(name: step["name"], kind: step["kind"] == "compose" ? "compose" : "higgsfield",
                                       model: step["model"], params: step["params"], status: "pending")
      end
    end

    def compose!(step)
      plan = spec_for(step)["compose_plan"]
      Dir.mktmpdir("compose") do |dir|
        media = Array(plan["layers"]).to_h { |layer| [ layer["media_path"], local_media(layer["media_path"], dir) ] }
        output = Frames::Composer.call(plan, media: media, to: File.join(dir, "#{step.name}.png"))
        File.open(output, "rb") do |io|
          step.output.attach(io: io, filename: "#{step.name}-#{step.id}.png", content_type: "image/png")
        end
      end
      step.update!(status: "done", error: nil)
    rescue Frames::Composer::Error => e
      step.update!(status: "failed", error: "Não foi possível montar o quadro #{step.name}: #{e.message}")
    end

    def submit!(step)
      spec = spec_for(step)
      check_start_frame_aspect!(spec) if step.kind == "higgsfield" && spec["kind"] == "kling"
      job_id = @gateway.submit(model: spec["model"], prompt: spec["prompt"], params: spec["params"].to_h, media: media_for(spec))
      step.update!(hf_job_id: job_id, status: "submitted", error: nil)
      # O prazo de 30 min já vai no 1º poll: um retry dessa execução não recomeça a contagem.
      PollRenderStepJob.perform_later(step, PollRenderStepJob::TIMEOUT.from_now.iso8601)
    rescue Higgsfield::RequestError, Higgsfield::ConfigurationError => e
      step.update!(status: "failed", error: e.message)
    end

    # D6: o Kling herda o aspecto do quadro inicial. Mede o arquivo do step de origem antes de gastar o vídeo.
    def check_start_frame_aspect!(spec)
      match = STEP_REF.match(spec.dig("inputs", "start_image").to_s) or return
      source = @creative.render_steps.find_by!(name: match[1])
      return unless source.output.attached?

      aspect = source.output.blob.open { |file| Media::Probe.call(file.path).aspect }
      wanted = spec.dig("params", "aspect_ratio")
      return if aspect == wanted

      raise Higgsfield::RequestError, "o quadro inicial saiu em #{aspect}, mas o vídeo é #{wanted}; o Kling herdaria o aspecto errado"
    end

    def media_for(spec)
      inputs = spec["inputs"].to_h
      items = Array(inputs["image_references"]).map { { value: resolve(_1), role: ROLES["image_references"] } }
      items << { value: resolve(inputs["start_image"]), role: ROLES["start_image"] } if inputs["start_image"].present?
      items << { value: resolve(inputs["end_image"]), role: ROLES["end_image"] } if inputs["end_image"].present?
      items
    end

    def resolve(ref)
      if (match = STEP_REF.match(ref))
        source = @creative.render_steps.find_by!(name: match[1])
        raise Error, "o step #{source.name} ainda não terminou" unless source.status == "done"
        return source.hf_job_id if source.kind == "higgsfield" && source.hf_job_id.present?

        upload(source.output)
      else
        media = @creative.project.media_inputs.find_by(path: ref) or raise Error, "mídia #{ref} não existe no projeto"
        upload(media.file)
      end
    end

    def upload(attachment)
      raise Error, "arquivo ausente para upload" unless attachment.attached?

      attachment.blob.open { |file| @gateway.upload(file.path, content_type: attachment.content_type) }
    end

    def local_media(path, dir)
      media = @creative.project.media_inputs.find_by(path: path) or raise Frames::Composer::Error, "mídia não encontrada: #{path}"
      target = File.join(dir, "#{media.id}#{File.extname(media.file.filename.to_s)}")
      File.binwrite(target, media.file.download)
      target
    end

    def finish!
      main = @creative.render_steps.find_by!(name: "main")
      @creative.result.attach(main.output.blob)
      @creative.update!(status: "done", error: nil) # T11 troca por reviewing + P5
      :done
    end

    def fail!(step)
      @creative.update!(status: "failed", error: "O passo #{step.name} falhou: #{step.error}")
      :failed
    end
  end
end
