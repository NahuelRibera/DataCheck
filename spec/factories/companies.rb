FactoryBot.define do
  factory :company do
    sequence(:name) { |n| "Acme Robotics #{n}" }
    sequence(:external_id) { |n| "ORG-#{n}" }
  end
end
