module ProjectsHelper
  ANALYSIS_STEPS = [ "baixando repo", "lendo arquivos", "analisando produto" ].freeze

  def project_title(project)
    project.owner && project.name ? "#{project.owner}/#{project.name}" : "Repositório"
  end

  # Estado de cada etapa da linha do tempo: :done, :current ou :pending.
  # Falhou: nenhuma etapa fica em andamento; o erro aparece no próprio bloco.
  def analysis_steps(project)
    return ANALYSIS_STEPS.map { |label| [ label, :pending ] } if project.status == "failed"

    index = analysis_step_index(project)
    ANALYSIS_STEPS.each_with_index.map do |label, i|
      state = if i < index then :done
      elsif i == index then :current
      else :pending
      end
      [ label, state ]
    end
  end

  # Índice da etapa em andamento. Em ingesting, o commit gravado marca o fim do download: daí em diante, lendo arquivos.
  def analysis_step_index(project)
    case project.status
    when "draft" then 0
    when "ingesting" then project.commit_sha.present? ? 1 : 0
    when "analyzing" then 2
    else ANALYSIS_STEPS.size
    end
  end

  def analysis_step_label(state)
    { done: "concluída", current: "em andamento", pending: "pendente" }.fetch(state)
  end

  def ignored_uploads_notice(project)
    names = Array(project.ignored_uploads)
    return if names.empty?

    if names.one?
      "1 foto ignorada: #{names.first} (não é uma imagem válida)"
    else
      "#{names.size} fotos ignoradas: #{names.join(', ')} (não são imagens válidas)"
    end
  end

  # Mensagens com mais de uma frase: cada frase começa com maiúscula.
  def capitalized_sentences(text)
    text.to_s.split(/(?<=[.!?])\s+/).map(&:upcase_first).join(" ")
  end

  def brief_audiences(project)
    Array(project.brief.is_a?(Hash) ? project.brief["audiences"] : nil)
  end

  def audience_name(project)
    audience = project.audience.is_a?(Hash) ? project.audience : {}
    audience["name"].presence || "Outro público"
  end

  # Ângulos prontos: o P2 grava { "audience_summary", "angles" }.
  def angle_list(project)
    Array(project.angles.is_a?(Hash) ? project.angles["angles"] : nil)
  end

  def creative_groups
    { "image" => "Imagens", "vertical" => "Vídeos verticais 9:16", "horizontal" => "Vídeos horizontais 16:9" }
  end

  # Créditos estimados de um criativo (Costs::Estimator, em cache). Nil se a Higgsfield não responder.
  def creative_credits(creative)
    Costs::Estimator.for(creative).total
  rescue Higgsfield::Error
    nil
  end

  def credits_label(credits)
    return "estimativa indisponível" if credits.nil?

    "≈ #{Higgsfield::BalanceGuard.format_credits(credits)} créditos"
  end

  # Texto do botão Gerar com o total dos marcados; sem estimativa completa, só "Gerar".
  def generate_label(creatives)
    selected = creatives.select(&:selected)
    totals = selected.map { |creative| creative_credits(creative) }
    return "Gerar" if selected.empty? || totals.any?(&:nil?)

    "Gerar (#{credits_label(totals.sum)})"
  end

  def creative_format(creative)
    duration = creative.duration ? "#{creative.duration} s" : "imagem"
    "#{creative.aspect_ratio} · #{duration}"
  end

  RECIPE_LABELS = {
    "nb_image" => "Imagem (Nano Banana)",
    "kling_reference" => "Vídeo com referência (Kling)",
    "kling_magic" => "Transformação em plano único (Kling)",
    "kling_keyframes" => "Quadro inicial e final (Kling)"
  }.freeze

  def recipe_label(recipe)
    RECIPE_LABELS.fetch(recipe, recipe)
  end

  # Promessas do brief: "can_claim" (pode dizer) ou "must_not_claim" (não pode dizer), só o texto.
  def brief_claims(project, key)
    items = project.brief.is_a?(Hash) ? Array(project.brief[key]) : []
    items.map { |item| item.is_a?(Hash) ? item["claim"] : item }.compact_blank
  end
end
