module ProjectsHelper
  ANALYSIS_STEPS = [ "baixando repo", "lendo arquivos", "analisando produto" ].freeze

  # Estado de cada etapa da linha do tempo: :done, :current ou :pending.
  # Falhou: nenhuma etapa fica em andamento; o erro aparece no próprio bloco.
  def analysis_steps(project)
    return ANALYSIS_STEPS.map { |label| [ label, :pending ] } if project.status == "failed"

    index = { "draft" => 0, "ingesting" => 0, "analyzing" => 2 }.fetch(project.status, ANALYSIS_STEPS.size)
    ANALYSIS_STEPS.each_with_index.map do |label, i|
      state = if i < index then :done
      elsif i == index then :current
      else :pending
      end
      [ label, state ]
    end
  end

  def analysis_step_label(state)
    { done: "concluída", current: "em andamento", pending: "pendente" }.fetch(state)
  end
end
