require "rails_helper"

RSpec.describe Employee, type: :model do
  it "is valid with a minimal valid factory" do
    expect(build(:employee)).to be_valid
  end

  it "requires external_id to be unique within a company" do
    company = create(:company)
    create(:employee, company: company, external_id: "EMP-1")
    duplicate = build(:employee, company: company, external_id: "EMP-1")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:external_id]).to be_present
  end

  it "allows the same external_id across different companies" do
    create(:employee, external_id: "EMP-SAME")
    other_company_employee = build(:employee, external_id: "EMP-SAME")

    expect(other_company_employee).to be_valid
  end

  it "enforces external_id uniqueness at the database level" do
    company = create(:company)
    create(:employee, company: company, external_id: "EMP-DB")

    expect do
      build(:employee, company: company, external_id: "EMP-DB").save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects a negative salary" do
    expect(build(:employee, gross_salary_cents: -1)).not_to be_valid
  end

  it "rejects an invalid email format but allows a blank one" do
    expect(build(:employee, email: "not-an-email")).not_to be_valid
    expect(build(:employee, email: "")).to be_valid
  end

  it "requires the manager to belong to the same company" do
    manager = create(:employee)
    other_company_employee = build(:employee, manager: manager)

    expect(other_company_employee).not_to be_valid
  end
end
