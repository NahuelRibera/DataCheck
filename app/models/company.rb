class Company < ApplicationRecord
  has_many :departments, dependent: :destroy
  has_many :employees, dependent: :destroy
  has_many :import_runs, dependent: :destroy

  validates :name, presence: true
  validates :external_id, presence: true, uniqueness: true

  # Employee#manager_id is a self-referential FK with no ON DELETE clause
  # (deliberately -- see Employee model: an app-level accident shouldn't be
  # able to silently orphan a manager reference). That means destroying a
  # company's employees in any order can hit a foreign key violation on
  # whichever employee still has direct reports. Break those references
  # first -- `prepend: true` so this runs before the `dependent: :destroy`
  # association callbacks below, not after.
  before_destroy :clear_employee_manager_references, prepend: true

  private

  def clear_employee_manager_references
    employees.where.not(manager_id: nil).update_all(manager_id: nil)
  end
end
