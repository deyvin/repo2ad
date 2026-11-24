class Creative < ApplicationRecord
  GROUPS = %w[image vertical horizontal].freeze
  RECIPES = %w[nb_image kling_reference kling_keyframes kling_magic].freeze
  STATUSES = %w[proposed queued prompting rendering reviewing done failed].freeze

  attribute :status, :string, default: "proposed"

  belongs_to :project
  has_many :render_steps, dependent: :destroy
  has_one_attached :result

  validates :group, inclusion: { in: GROUPS }
  validates :recipe, inclusion: { in: RECIPES }
  validates :status, inclusion: { in: STATUSES }
end
