# §2 Resultado: os criativos selecionados de um projeto, com status ao vivo (Turbo Stream), QA, Baixar e Gerar de novo.
class ResultsController < ApplicationController
  def show
    @project = Project.find(params[:project_id])
    @creatives = helpers.result_creatives(@project)
  end
end
