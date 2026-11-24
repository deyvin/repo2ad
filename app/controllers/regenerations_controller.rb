# "Gerar de novo" manual (§1, §2 Resultado): a observação do usuário vai para creative.instructions e o criativo
# recomeça pelo P4. O diálogo fica na tela de resultado (TR); aqui só a ação.
class RegenerationsController < ApplicationController
  def create
    project = Project.find(params[:project_id])
    creative = project.creatives.find(params[:creative_id])

    unless creative.finished?
      return redirect_back fallback_location: project_path(project), alert: "O #{creative.code} ainda está sendo gerado."
    end

    Higgsfield::BalanceGuard.check!(Costs::Estimator.for(creative).total)
    Creative.transaction do
      project.transition_to!("generating") if project.status == "done"
      creative.update!(instructions: params[:instructions].to_s.strip.presence, status: "queued", error: nil, qa: nil)
    end
    PromptCreativeJob.perform_later(creative)
    redirect_back fallback_location: project_path(project), notice: "Gerando o #{creative.code} de novo."
  rescue Higgsfield::Error => e
    redirect_back fallback_location: project_path(project), alert: e.message
  end
end
