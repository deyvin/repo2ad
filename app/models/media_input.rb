class MediaInput < ApplicationRecord
  SOURCES = %w[repo upload].freeze
  # kind é preenchido pelo P1; antes disso fica vazio.
  KINDS = %w[screenshot photo logo diagram other].freeze

  belongs_to :project
  has_one_attached :file

  validates :source, inclusion: { in: SOURCES }
  validates :kind, inclusion: { in: KINDS }, allow_nil: true
end
