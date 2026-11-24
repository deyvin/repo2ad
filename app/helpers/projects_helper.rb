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
end
