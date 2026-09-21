class Employee < ApplicationRecord
  STATUSES = %w[active inactive terminated].freeze
  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  belongs_to :company
  belongs_to :department, optional: true
  belongs_to :manager, class_name: "Employee", optional: true

  has_many :direct_reports, class_name: "Employee", foreign_key: :manager_id, inverse_of: :manager
  has_many :employee_contracts, dependent: :destroy

  validates :external_id, presence: true, uniqueness: { scope: :company_id }
  validates :first_name, :last_name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :email, format: { with: EMAIL_FORMAT }, allow_blank: true
  validates :gross_salary_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :manager_belongs_to_same_company

  def full_name
    "#{first_name} #{last_name}"
  end

  private

  def manager_belongs_to_same_company
    return if manager.nil?

    errors.add(:manager, "must belong to the same company") if manager.company_id != company_id
  end
end
