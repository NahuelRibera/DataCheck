# frozen_string_literal: true

class GraphqlController < ApplicationController
  # This surface is read-only (no mutations -- see DataCheckSchema) and
  # doesn't use session-based auth, so there's no CSRF-relevant state for
  # the standard protect_from_forgery to guard. Without this, any real
  # client (curl, Postman, a documented `curl -X POST /graphql` example)
  # gets a 422 ActionController::InvalidAuthenticityToken instead of a
  # GraphQL response -- it only appears to work in RSpec because Rails
  # disables forgery protection in the test environment by default.
  skip_forgery_protection

  class InvalidVariables < StandardError; end

  def execute
    variables = prepare_variables(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]
    context = {
      # Query context goes here, for example:
      # current_user: current_user,
    }
    result = DataCheckSchema.execute(query, variables: variables, context: context, operation_name: operation_name)
    render json: result
  rescue InvalidVariables
    render_invalid_variables
  rescue StandardError => e
    raise e unless Rails.env.development?
    handle_error_in_development(e)
  end

  private

  # Handle variables in form data, JSON body, or a blank value
  def prepare_variables(variables_param)
    case variables_param
    when String
      if variables_param.present?
        parsed = JSON.parse(variables_param) || {}
        raise InvalidVariables unless parsed.is_a?(Hash)

        parsed
      else
        {}
      end
    when Hash
      variables_param
    when ActionController::Parameters
      variables_param.to_unsafe_hash # GraphQL-Ruby will validate name and type of incoming variables.
    when nil
      {}
    else
      raise InvalidVariables
    end
  rescue JSON::ParserError
    raise InvalidVariables
  end

  def render_invalid_variables
    # Generic on purpose: never echo the submitted input.
    render json: { errors: [{ message: "Invalid variables parameter" }] }, status: :bad_request
  end

  def handle_error_in_development(e)
    logger.error e.message
    logger.error e.backtrace.join("\n")

    render json: { errors: [{ message: e.message, backtrace: e.backtrace }], data: {} }, status: 500
  end
end
