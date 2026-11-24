class Project < ApplicationRecord
  STATUSES = %w[draft ingesting analyzing awaiting_audience planning awaiting_selection generating done failed].freeze

  # Caminho feliz (§1 e §3.5). "failed" vale a partir de qualquer status que não seja "failed"; por isso não aparece aqui.
  NEXT_STATUSES = {
    "draft" => %w[ingesting],
    "ingesting" => %w[analyzing],
    "analyzing" => %w[awaiting_audience],
    "awaiting_audience" => %w[planning],
    "planning" => %w[awaiting_selection],
    "awaiting_selection" => %w[generating],
    "generating" => %w[done],
    "done" => [],
    "failed" => []
  }.freeze

  class InvalidTransition < StandardError; end

  attribute :status, :string, default: "draft"

  has_many :media_inputs, dependent: :destroy
  has_many :creatives, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :error, presence: true, if: -> { status == "failed" }

  def can_transition_to?(new_status)
    return status != "failed" if new_status == "failed"

    NEXT_STATUSES.fetch(status, []).include?(new_status)
  end

  def transition_to!(new_status, error: nil)
    raise InvalidTransition, "transição inválida: #{status} -> #{new_status}" unless can_transition_to?(new_status)
    raise ArgumentError, "error é obrigatório ao marcar como failed" if new_status == "failed" && error.blank?

    update!(status: new_status, error: new_status == "failed" ? error : nil)
  end
end
