class CreateAuditEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :audit_events do |t|
      t.references :import_run, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :message, null: false
      t.jsonb :metadata, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :audit_events, [:import_run_id, :created_at]
  end
end
