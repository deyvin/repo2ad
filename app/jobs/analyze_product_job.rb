# TODO(T4): P1, o brief do produto via Claude::Stage (OpenRouter). Por enquanto só existe para o
# IngestRepoJob enfileirar; não faz nada.
class AnalyzeProductJob < ApplicationJob
  queue_as :default

  def perform(_project_id)
    # TODO(T4): implementar o P1.
  end
end
