# Readiness check for the deploy script: the app booted AND can query Postgres.
# /up (Rails::HealthController) only proves the app booted.
#
# Inherits from ActionController::API, not ApplicationController, so the
# authentication and tenant concerns added there later never apply here.
class ReadinessController < ActionController::API
  def show
    ActiveRecord::Base.with_connection { |connection| connection.select_value("SELECT 1") }
    render json: { status: "ok" }
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.error("Readiness check failed: #{error.class}: #{error.message}")
    render json: { status: "unavailable" }, status: :service_unavailable
  end
end
