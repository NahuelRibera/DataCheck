FactoryBot.define do
  factory :audit_event do
    import_run
    event_type { "import_uploaded" }
    message { "Import file uploaded." }
    metadata { {} }
  end
end
