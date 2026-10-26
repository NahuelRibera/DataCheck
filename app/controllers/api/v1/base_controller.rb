module Api
  module V1
    class BaseController < ActionController::API
      # Handlers declared later take precedence, so the catch-all comes first.
      rescue_from StandardError, with: :render_internal_error
      rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_malformed_body
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActionController::ParameterMissing, with: :render_bad_request
      rescue_from Imports::ExecuteService::ExecutionBlockedError, with: :render_execution_blocked

      private

      def render_not_found
        render json: { error: "not found" }, status: :not_found
      end

      # Fixed text on purpose: the exception message names the missing key.
      def render_bad_request
        render json: { error: "bad request: missing required parameter" }, status: :bad_request
      end

      # Fixed text on purpose: the parser message can quote the request body.
      def render_malformed_body
        render json: { error: "bad request: malformed JSON body" }, status: :bad_request
      end

      def render_internal_error(exception)
        # Class name only: the message may contain record values.
        logger.error "API request failed: #{exception.class.name}"
        render json: { error: "internal server error" }, status: :internal_server_error
      end

      def render_execution_blocked
        render json: { error: "execution refused: blocking issues remain" }, status: :unprocessable_content
      end
    end
  end
end
