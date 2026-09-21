# A small, deliberately read-only GraphQL surface over operational data
# (ImportRuns and their issues). No mutations -- write actions go through
# the REST API / controllers, which own transaction and audit boundaries.
class DataCheckSchema < GraphQL::Schema
  query(Types::QueryType)

  max_depth(15)
  max_query_string_tokens(5000)
  validate_max_errors(100)
end
