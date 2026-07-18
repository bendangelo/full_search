# frozen_string_literal: true

require "test_helper"

class FullSearch::MultiSearchTest < ActiveSupport::TestCase
  def setup
    @customer_model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
      end
    end
    @customer_model.table_name = "customers"

    @vehicle_model = Class.new(Vehicle) do
      full_search do
        field :license_plate, weight: 5
        filter :account_id, required: true
      end
    end
    @vehicle_model.table_name = "vehicles"
  end

  def teardown
    Customer.delete_all
    Vehicle.delete_all
  end

  def test_returns_grouped_results_with_has_more
    account = Account.create!(name: "Acme")
    10.times { |i| @customer_model.create!(account_id: account.id, first_name: "User #{i}") }
    @vehicle_model.create!(account_id: account.id, license_plate: "USERPLATE")
    FullSearch::Index.rebuild!(@customer_model)
    FullSearch::Index.rebuild!(@vehicle_model)

    result = FullSearch.multi_search(
      query: "User",
      groups: [
        { key: :customers, label: "Customers", model: @customer_model,
          filters: { account_id: account.id }, limit: 8 },
        { key: :vehicles, label: "Vehicles", model: @vehicle_model,
          filters: { account_id: account.id }, limit: 8 }
      ]
    )

    customers_group = result[:groups].find { |g| g[:key] == :customers }
    vehicles_group = result[:groups].find { |g| g[:key] == :vehicles }

    assert_equal 8, customers_group[:results].size
    assert customers_group[:has_more]
    assert_equal 1, vehicles_group[:results].size
    assert_not vehicles_group[:has_more]
    assert_equal 9, result[:total_count]
  end

  def test_applies_scope_block
    account = Account.create!(name: "Acme")
    @customer_model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(@customer_model)

    called = false
    result = FullSearch.multi_search(
      query: "Sam",
      groups: [
        { key: :customers, label: "Customers", model: @customer_model,
          filters: { account_id: account.id },
          scope: ->(rel) { called = true; rel } }
      ]
    )

    assert called
    assert_equal 1, result[:total_count]
  end
end
