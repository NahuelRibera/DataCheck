class Department < ApplicationRecord
  belongs_to :company
  has_many :employees, dependent: :nullify

  validates :name, presence: true
  validates :external_id, presence: true, uniqueness: { scope: :company_id }
end
