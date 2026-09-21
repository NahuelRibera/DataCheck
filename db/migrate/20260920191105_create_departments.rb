class CreateDepartments < ActiveRecord::Migration[7.1]
  def change
    create_table :departments do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.string :external_id, null: false

      t.timestamps
    end

    add_index :departments, [:company_id, :external_id], unique: true, name: "index_departments_on_company_and_external_id"
  end
end
