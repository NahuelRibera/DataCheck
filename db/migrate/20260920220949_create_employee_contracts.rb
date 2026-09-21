class CreateEmployeeContracts < ActiveRecord::Migration[7.1]
  def change
    create_table :employee_contracts do |t|
      t.references :employee, null: false, foreign_key: true
      t.date :start_date, null: false
      t.date :end_date
      t.integer :salary_cents, null: false
      t.string :contract_type, null: false, default: "permanent"

      t.timestamps
    end

    add_index :employee_contracts, [:employee_id, :start_date]
  end
end
