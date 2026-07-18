# frozen_string_literal: true

require "test_helper"

class FullSearch::ExactMatchTest < ActiveSupport::TestCase
  def setup
    @vehicle_model = Class.new(Vehicle) do
      full_search do
        field :license_plate, weight: 5
        exact_match :vin, source: -> { vin }
        filter :account_id, required: true
      end
    end
    @vehicle_model.table_name = "vehicles"
  end

  def teardown
    Vehicle.delete_all
  end

  def test_exact_match_returns_ids
    account = Account.create!(name: "Acme")
    vehicle = @vehicle_model.create!(account_id: account.id, vin: "1HGCM82633A004352")

    ids = FullSearch::ExactMatch.ids_for(@vehicle_model, "1HGCM82633A004352", { account_id: account.id })
    assert_includes ids, vehicle.id
  end
end
