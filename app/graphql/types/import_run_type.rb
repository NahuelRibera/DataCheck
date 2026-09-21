module Types
  class ImportRunType < Types::BaseObject
    field :id, ID, null: false
    field :company_name, String, null: false
    field :filename, String, null: false
    field :status, String, null: false
    field :source_record_count, Integer, null: false
    field :valid_record_count, Integer, null: false
    field :issue_count, Integer, null: false
    field :blocking_issue_count, Integer, null: false
    field :create_count, Integer, null: false
    field :update_count, Integer, null: false
    field :skip_count, Integer, null: false
    field :reject_count, Integer, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    field :issues, [Types::ImportIssueType], null: false do
      argument :severity, String, required: false
    end

    def company_name
      object.company.name
    end

    def issues(severity: nil)
      scope = object.import_issues.order(:row_number)
      severity ? scope.where(severity: severity) : scope
    end
  end
end
