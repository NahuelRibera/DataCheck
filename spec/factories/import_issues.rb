FactoryBot.define do
  factory :import_issue do
    import_run
    row_number { 1 }
    external_id { "EMP-0001" }
    issue_type { "orphan_manager" }
    severity { "blocking" }
    field_name { "manager_external_id" }
    message { "Manager reference does not exist in this import or target company." }
    metadata { {} }
  end
end
