class CreateCompanies < ActiveRecord::Migration[7.1]
  def change
    create_table :companies do |t|
      t.string :name, null: false
      t.string :external_id, null: false

      t.timestamps
    end

    add_index :companies, :external_id, unique: true
  end
end
