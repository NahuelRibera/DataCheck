class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_not_found
    respond_to do |format|
      format.html { render "errors/not_found", status: :not_found }
      format.json { render json: { error: "not found" }, status: :not_found }
    end
  end
end
