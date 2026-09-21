FactoryBot.define do
  factory :employee do
    company
    department
    manager { nil }
    sequence(:external_id) { |n| "EMP-#{n}" }
    sequence(:first_name) { |n| "First#{n}" }
    sequence(:last_name) { |n| "Last#{n}" }
    sequence(:email) { |n| "employee#{n}@example.com" }
    start_date { Date.new(2024, 1, 1) }
    gross_salary_cents { 5_000_000 }
    status { "active" }
  end
end
