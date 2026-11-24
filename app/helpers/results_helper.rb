module ResultsHelper
  GROUP_ORDER = %w[image vertical horizontal].freeze
  GROUP_LABELS = { "image" => "Imagem", "vertical" => "Vídeo vertical", "horizontal" => "Vídeo horizontal" }.freeze
  STATUS_LABELS = {
    "proposed" => "Aguardando", "queued" => "Na fila", "prompting" => "Escrevendo o pedido de geração",
    "rendering" => "Gerando na Higgsfield", "reviewing" => "Revisando o resultado"
  }.freeze
  VERDICTS = {
    "approve" => "Aprovado", "approve_with_notes" => "Aprovado com ressalvas", "regenerate" => "A revisão sugere gerar de novo"
  }.freeze
  SEVERITIES = { "alta" => "Alta", "media" => "Média", "baixa" => "Baixa" }.freeze

  def result_creatives(project)
    project.creatives.where(selected: true).with_attached_result.to_a
           .sort_by { |creative| [ GROUP_ORDER.index(creative.group) || 9, creative.code.to_s[/\d+/].to_i ] }
  end

  def creative_format(creative)
    label = "#{GROUP_LABELS.fetch(creative.group, creative.group)} #{creative.aspect_ratio}"
    creative.duration ? "#{label}, #{creative.duration} s" : label
  end

  def creative_aspect_style(creative)
    width, height = creative.aspect_ratio.to_s.split(":").map(&:to_i)
    width.to_i.positive? && height.to_i.positive? ? "aspect-ratio: #{width} / #{height}" : "aspect-ratio: 1 / 1"
  end

  def creative_in_progress?(creative) = !creative.finished?

  def creative_video?(creative) = creative.result.attached? && creative.result.content_type.to_s.start_with?("video/")

  # Imagem para a grade: versão reduzida (o original fica no Baixar).
  def creative_preview_path(creative)
    return rails_blob_path(creative.result, only_path: true) if creative_video?(creative) || !creative.result.variable?

    rails_representation_path(creative.result.variant(resize_to_limit: [ 1200, 1200 ]), only_path: true)
  end

  def creative_status_label(creative) = STATUS_LABELS.fetch(creative.status, creative.status)

  def qa_verdict(creative) = creative.qa.is_a?(Hash) ? creative.qa["verdict"] : nil

  # A revisão (P5) só sugere refazer; o usuário aceita pelo diálogo, com a correção já preenchida.
  def qa_suggests_regeneration?(creative) = creative.finished? && qa_verdict(creative) == "regenerate"

  def qa_fix_instructions(creative) = creative.qa.is_a?(Hash) ? creative.qa["fix_instructions"].to_s : ""

  def accept_suggestion_label(creative)
    credits = creative_credits(creative)
    credits ? "Aceitar sugestão e gerar de novo (#{credits_label(credits)})" : "Aceitar sugestão e gerar de novo"
  end

  def results_summary(creatives)
    done = creatives.count { _1.status == "done" }
    failed = creatives.count { _1.status == "failed" }
    running = creatives.size - done - failed
    parts = [ "#{done} de #{creatives.size} #{creatives.size == 1 ? "pronto" : "prontos"}" ]
    parts << "#{failed} com falha" if failed.positive?
    parts << "#{running} em andamento" if running.positive?
    parts.join(", ")
  end
end
