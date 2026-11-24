class RenderStep < ApplicationRecord
  # name e kind são da §3.4; status segue o ciclo do PollRenderStepJob (§3.5).
  NAMES = %w[start_frame end_frame main].freeze
  KINDS = %w[compose higgsfield].freeze
  STATUSES = %w[pending submitted running done failed].freeze

  attribute :status, :string, default: "pending"

  belongs_to :creative
  has_one_attached :output

  validates :name, inclusion: { in: NAMES }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
end
