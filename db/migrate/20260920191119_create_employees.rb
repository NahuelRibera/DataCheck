class CreateEmployees < ActiveRecord::Migration[7.1]
  def change
    create_table :employees do |t|
      t.references :company, null: false, foreign_key: true
      t.references :department, null: true, foreign_key: true
      t.bigint :manager_id
      t.string :external_id, null: false
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email
      t.date :start_date
      t.integer :gross_salary_cents
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :employees, [:company_id, :external_id], unique: true, name: "index_employees_on_company_and_external_id"
    add_index :employees, [:company_id, :manager_id]
    add_foreign_key :employees, :employees, column: :manager_id
    add_check_constraint :employees, "gross_salary_cents IS NULL OR gross_salary_cents >= 0", name: "employees_gross_salary_non_negative"
  end
end
