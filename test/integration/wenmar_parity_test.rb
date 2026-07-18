# frozen_string_literal: true

require "test_helper"

class WenmarParityTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Acme")

    @customer_model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        field :company_name, weight: 4
        field :fleet_identifier, weight: 2
        filter :account_id, required: true
        filter :customer_type
      end
    end
    @customer_model.table_name = "customers"

    @vehicle_model = Class.new(Vehicle) do
      belongs_to :customer, optional: true, class_name: "Customer"
      full_search do
        field :license_plate, weight: 5
        field :vin_last8, weight: 2, source: -> { vin&.last(8)&.upcase }
        field :make, weight: 4
        field :model, weight: 4
        exact_match :vin, source: -> { vin }
        filter :account_id, required: true
      end
    end
    @vehicle_model.table_name = "vehicles"

    FullSearch::Index.rebuild!(@customer_model)
    FullSearch::Index.rebuild!(@vehicle_model)
  end

  def teardown
    FullSearch::Index.drop!(@customer_model) rescue nil
    FullSearch::Index.drop!(@vehicle_model) rescue nil
  end

  def test_customer_prefix_search
    customer = @customer_model.create!(account_id: @account.id, first_name: "Samantha", last_name: "Smith")
    results = @customer_model.full_search("Samantha", filters: { account_id: @account.id })
    assert_includes results.to_a, customer
  end

  def test_vehicle_exact_vin_search
    vehicle = @vehicle_model.create!(account_id: @account.id, vin: "1HGCM82633A004352")
    results = @vehicle_model.full_search("1HGCM82633A004352", filters: { account_id: @account.id })
    assert_includes results.to_a, vehicle
  end

  def test_search_respects_required_filter
    assert_raises(FullSearch::MissingRequiredFilterError) do
      @vehicle_model.full_search("test", filters: {})
    end
  end
end
