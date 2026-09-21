FactoryBot.define do
  factory :import_run do
    company
    filename { "clean_employees.csv" }
    status { "uploaded" }
    source_record_count { 0 }
    valid_record_count { 0 }
    issue_count { 0 }
    blocking_issue_count { 0 }
    create_count { 0 }
    update_count { 0 }
    skip_count { 0 }
    reject_count { 0 }
    metadata { {} }
  end
end
