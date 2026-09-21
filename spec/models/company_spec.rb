require "rails_helper"

RSpec.describe Company, type: :model do
  it "requires a unique external_id" do
    create(:company, external_id: "ORG-1")
    duplicate = build(:company, external_id: "ORG-1")

    expect(duplicate).not_to be_valid
  end

  it "can be destroyed even when its employees have self-referential manager links" do
    company = create(:company)
    manager = create(:employee, company: company)
    create(:employee, company: company, manager: manager)

    expect { company.destroy! }.not_to raise_error
    expect(Employee.where(company_id: company.id)).to be_empty
  end
end
