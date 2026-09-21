module Types
  class ImportIssueType < Types::BaseObject
    field :id, ID, null: false
    field :row_number, Integer, null: true
    field :external_id, String, null: true
    field :issue_type, String, null: false
    field :severity, String, null: false
    field :field_name, String, null: true
    field :message, String, null: false
  end
end
