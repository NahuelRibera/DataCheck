class CreateImportIssues < ActiveRecord::Migration[7.1]
  def change
    create_table :import_issues do |t|
      t.references :import_run, null: false, foreign_key: true
      t.integer :row_number
      t.string :external_id
      t.string :issue_type, null: false
      t.string :severity, null: false
      t.string :field_name
      t.text :message, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :import_issues, [:import_run_id, :severity]
    add_index :import_issues, [:import_run_id, :issue_type]
    add_check_constraint :import_issues, "severity IN ('warning', 'blocking')", name: "import_issues_severity_check"
  end
end
