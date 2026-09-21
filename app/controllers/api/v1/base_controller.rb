module Api
  module V1
    class BaseController < ActionController::API
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActionController::ParameterMissing, with: :render_bad_request
      rescue_from Imports::ExecuteService::ExecutionBlockedError, with: :render_execution_blocked

      private

      def render_not_found
        render json: { error: "not found" }, status: :not_found
      end

      def render_bad_request(exception)
        render json: { error: exception.message }, status: :bad_request
      end

      def render_execution_blocked
        render json: { error: "execution refused: blocking issues remain" }, status: :unprocessable_content
      end
    end
  end
end
