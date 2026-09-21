class CreateImportRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :import_runs do |t|
      t.references :company, null: false, foreign_key: true
      t.string :filename, null: false
      t.string :status, null: false, default: "uploaded"
      t.integer :source_record_count, null: false, default: 0
      t.integer :valid_record_count, null: false, default: 0
      t.integer :issue_count, null: false, default: 0
      t.integer :blocking_issue_count, null: false, default: 0
      t.integer :create_count, null: false, default: 0
      t.integer :update_count, null: false, default: 0
      t.integer :skip_count, null: false, default: 0
      t.integer :reject_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :import_runs, :status
    add_index :import_runs, [:company_id, :created_at]
  end
end
