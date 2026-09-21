FactoryBot.define do
  factory :employee_contract do
    employee
    start_date { Date.new(2024, 1, 1) }
    end_date { nil }
    salary_cents { 5_000_000 }
    contract_type { "permanent" }
  end
end
