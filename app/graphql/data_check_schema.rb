# A small, deliberately read-only GraphQL surface over operational data
# (ImportRuns and their issues). No mutations -- write actions go through
# the REST API / controllers, which own transaction and audit boundaries.
class DataCheckSchema < GraphQL::Schema
  query(Types::QueryType)

  # Every field costs 1 (lists are not multiplied). The full ImportRun +
  # issues selection is ~22, so 200 leaves ample room for real dashboard
  # queries while rejecting wide, alias-multiplied ones. The schema is only
  # 3 levels deep (importRuns > issues > fields), so depth 6 has headroom.
  max_complexity(200)
  max_depth(6)
  max_query_string_tokens(5000)
  validate_max_errors(100)
end
