# Tela Público (§2): escolher um dos públicos do brief ou descrever outro. Ao escolher, o P2 gera os ângulos.
class AudiencesController < ApplicationController
  CHOSEN_STATUSES = %w[planning awaiting_selection generating done].freeze

  before_action :set_project

  def show
    if @project.status == "awaiting_audience"
      render :choose
    elsif CHOSEN_STATUSES.include?(@project.status)
      render :chosen
    else
      redirect_to project_path(@project)
    end
  end

  def update
    return redirect_to(project_audience_path(@project), status: :see_other) unless @project.status == "awaiting_audience"

    audience = chosen_audience
    if audience.nil?
      @error = chosen_error
      return render :choose, status: :unprocessable_entity
    end

    Project.transaction do
      @project.update!(audience: audience)
      @project.transition_to!("planning")
    end
    BuildAnglesJob.perform_later(@project.id)
    redirect_to project_audience_path(@project), status: :see_other
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  # Um público do brief (pela chave) ou um texto livre do usuário. Nil quando nada válido foi escolhido.
  def chosen_audience
    choice = params[:audience_choice].to_s
    if choice == "outro"
      text = params[:custom_audience].to_s.strip
      { "source" => "custom", "description" => text } if text.present?
    else
      audience = Array(@project.brief.is_a?(Hash) ? @project.brief["audiences"] : nil).find { |item| item["key"] == choice }
      audience&.merge("source" => "brief")
    end
  end

  def chosen_error
    params[:audience_choice].to_s == "outro" ? "Descreva o público em uma frase." : "Escolha um dos públicos ou descreva outro."
  end
end
