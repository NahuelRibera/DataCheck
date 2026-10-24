module Types
  class QueryType < Types::BaseObject
    MAX_IMPORT_RUNS = 50

    field :import_run, Types::ImportRunType, null: true do
      argument :id, ID, required: true
    end

    field :import_runs, [Types::ImportRunType], null: false

    def import_run(id:)
      ImportRun.find_by(id: id)
    end

    def import_runs
      ImportRun.includes(:company).recent_first.order(id: :desc).limit(MAX_IMPORT_RUNS)
    end
  end
end
