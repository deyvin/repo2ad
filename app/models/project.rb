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
  # Vale para qualquer update!(status:), não só para transition_to!. A criação fica livre.
  validate :status_follows_flow, on: :update, if: :will_save_change_to_status?
  # Título e linha do tempo da tela de análise se atualizam sozinhos (Turbo Stream) quando o que aparece muda.
  after_update_commit :broadcast_analysis, if: :analysis_changed?

  def self.transition_allowed?(from, to)
    from = from.to_s
    to = to.to_s
    return from != "failed" if to == "failed"

    NEXT_STATUSES.fetch(from, []).include?(to)
  end

  def can_transition_to?(new_status)
    self.class.transition_allowed?(status, new_status)
  end

  def transition_to!(new_status, error: nil)
    new_status = new_status.to_s
    raise InvalidTransition, "transição inválida: #{status} -> #{new_status}" unless can_transition_to?(new_status)
    raise ArgumentError, "error é obrigatório ao marcar como failed" if new_status == "failed" && error.blank?

    update!(status: new_status, error: new_status == "failed" ? error : nil)
  end

  private

  def status_follows_flow
    return if self.class.transition_allowed?(status_in_database, status)

    errors.add(:status, "não pode passar de #{status_in_database} para #{status}")
  end

  def analysis_changed?
    saved_change_to_status? || saved_change_to_owner? || saved_change_to_name? ||
      saved_change_to_commit_sha? || saved_change_to_ignored_uploads?
  end

  def broadcast_analysis
    broadcast_replace_to self, target: ActionView::RecordIdentifier.dom_id(self, :title),
                               partial: "projects/title", locals: { project: self }
    broadcast_replace_to self, target: ActionView::RecordIdentifier.dom_id(self, :timeline),
                               partial: "projects/timeline", locals: { project: self }
  end
end
