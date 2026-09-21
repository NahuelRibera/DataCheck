require "rails_helper"

RSpec.describe Department, type: :model do
  it "requires external_id to be unique within a company" do
    company = create(:company)
    create(:department, company: company, external_id: "DEPT-1")
    duplicate = build(:department, company: company, external_id: "DEPT-1")

    expect(duplicate).not_to be_valid
  end

  it "allows the same external_id across different companies" do
    create(:department, external_id: "DEPT-SAME")
    expect(build(:department, external_id: "DEPT-SAME")).to be_valid
  end
end
