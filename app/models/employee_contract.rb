class EmployeeContract < ApplicationRecord
  belongs_to :employee

  validates :start_date, presence: true
  validates :salary_cents, numericality: { greater_than_or_equal_to: 0 }
end
