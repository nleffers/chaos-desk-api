require "rails_helper"

RSpec.describe "Health checks", type: :request do
  describe "GET /up" do
    it "returns 200 when the app has booted" do
      get "/up"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /ready" do
    it "returns 200 when Postgres answers a query" do
      get "/ready"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("status" => "ok")
    end

    it "returns 503 when Postgres can't be queried" do
      allow(ActiveRecord::Base).to receive(:with_connection)
        .and_raise(ActiveRecord::ConnectionNotEstablished, "connection refused")

      get "/ready"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq("status" => "unavailable")
    end
  end
end
