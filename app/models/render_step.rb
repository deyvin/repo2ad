class RenderStep < ApplicationRecord
  belongs_to :creative
  has_one_attached :output
end
