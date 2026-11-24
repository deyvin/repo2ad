class Creative < ApplicationRecord
  GROUPS = %w[image vertical horizontal].freeze
  RECIPES = %w[nb_image kling_reference kling_keyframes kling_magic].freeze
  STATUSES = %w[proposed queued prompting rendering reviewing done failed].freeze
  FINISHED = %w[done failed].freeze

  attribute :status, :string, default: "proposed"

  belongs_to :project
  has_many :render_steps, dependent: :destroy
  has_one_attached :result

  validates :group, inclusion: { in: GROUPS }
  validates :recipe, inclusion: { in: RECIPES }
  validates :status, inclusion: { in: STATUSES }

  # O projeto volta para done quando o último criativo selecionado termina.
  after_update_commit -> { project.complete_generation! }, if: -> { saved_change_to_status? && status.in?(FINISHED) }

  # Tela de resultado ao vivo: o card do criativo e o resumo do topo (TR).
  after_update_commit :broadcast_result, if: -> { saved_change_to_status? || saved_change_to_qa? || saved_change_to_error? }

  def finished? = status.in?(FINISHED)

  private

  def broadcast_result
    broadcast_replace_to [ project, :results ], target: ActionView::RecordIdentifier.dom_id(self, :result),
                                               partial: "results/creative", locals: { creative: self }
    creatives = ApplicationController.helpers.result_creatives(project)
    broadcast_replace_to [ project, :results ], target: ActionView::RecordIdentifier.dom_id(project, :results_summary),
                                               partial: "results/summary", locals: { project: project, creatives: creatives }
  end
end
