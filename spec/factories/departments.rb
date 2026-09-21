FactoryBot.define do
  factory :department do
    company
    sequence(:name) { |n| "Department #{n}" }
    sequence(:external_id) { |n| "DEPT-#{n}" }
  end
end
