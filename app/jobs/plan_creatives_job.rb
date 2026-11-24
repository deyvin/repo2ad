# TODO(T6): P3, o cardápio de criativos, com a validação extra do §5.4. Por enquanto só existe para o
# BuildAnglesJob enfileirar; não faz nada.
class PlanCreativesJob < ApplicationJob
  queue_as :default

  def perform(_project_id)
    # TODO(T6): implementar o P3.
  end
end
