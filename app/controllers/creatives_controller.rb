# Tela Criativos (§2): cardápio do P3 agrupado, painel de promessas e "Gerar". O Gerar confere o saldo antes de
# qualquer geração: sem conexão ou sem créditos, nada muda e a tela diz o motivo.
class CreativesController < ApplicationController
  before_action :set_project

  def show
    case @project.status
    when "awaiting_selection", "planning" then render :show
    when "generating", "done" then redirect_to project_results_path(@project)
    else redirect_to project_path(@project)
    end
  end

  def create
    return redirect_to(project_creatives_path(@project), status: :see_other) unless @project.status == "awaiting_selection"

    chosen = @project.creatives.where(id: Array(params[:creative_ids]).map(&:to_i))
    return back_with_alert("Escolha pelo menos um criativo.") if chosen.empty?

    Project.transaction do
      @project.creatives.update_all(selected: false)
      chosen.update_all(selected: true, status: "queued")
      Higgsfield::BalanceGuard.check!(Costs::Estimator.for_selection(@project).total)
      @project.transition_to!("generating")
    end

    @project.creatives.where(selected: true).find_each { |creative| PromptCreativeJob.perform_later(creative) }
    redirect_to project_results_path(@project), status: :see_other
  rescue Higgsfield::Error => e
    back_with_alert(e.message)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def back_with_alert(message)
    redirect_to project_creatives_path(@project), alert: message, status: :see_other
  end
end
