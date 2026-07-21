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
        exact_match :license_plate
        filter :account_id, required: true
      end
    end
    @vehicle_model.table_name = "vehicles"
  end

  def teardown
    begin
      FullSearch::Index.drop!(@customer_model)
    rescue
      nil
    end
    begin
      FullSearch::Index.drop!(@vehicle_model)
    rescue
      nil
    end
    Customer.delete_all
    Vehicle.delete_all
  end

  def test_returns_grouped_results_with_has_more
    account = Account.create!(name: "Acme")
    10.times { |i| @customer_model.create!(account_id: account.id, first_name: "User #{i}") }
    @vehicle_model.create!(account_id: account.id, license_plate: "User")
    FullSearch::Index.rebuild!(@customer_model)
    FullSearch::Index.rebuild!(@vehicle_model)

    result = FullSearch.multi_search(
      query: "User",
      groups: [
        {key: :customers, label: "Customers", model: @customer_model,
         filters: {account_id: account.id}, limit: 8},
        {key: :vehicles, label: "Vehicles", model: @vehicle_model,
         filters: {account_id: account.id}, limit: 8}
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
        {key: :customers, label: "Customers", model: @customer_model,
         filters: {account_id: account.id},
         scope: ->(rel) {
           called = true
           rel
         }}
      ]
    )

    assert called
    assert_equal 1, result[:total_count]
  end

  def test_offset_shifts_results
    account = Account.create!(name: "Acme")
    5.times { |i| @customer_model.create!(account_id: account.id, first_name: "User #{i}") }
    FullSearch::Index.rebuild!(@customer_model)

    result = FullSearch.multi_search(
      query: "User",
      groups: [
        {key: :customers, label: "Customers", model: @customer_model,
         filters: {account_id: account.id}, limit: 3, offset: 2}
      ]
    )

    group = result[:groups].first
    assert_equal 3, group[:results].size
  end

  def test_returns_empty_with_empty_query
    account = Account.create!(name: "Acme")
    @customer_model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(@customer_model)

    result = FullSearch.multi_search(
      query: "",
      groups: [
        {key: :customers, label: "Customers", model: @customer_model,
         filters: {account_id: account.id}}
      ]
    )

    assert_equal 0, result[:total_count]
    assert result[:groups].first[:results].empty?
  end

  def test_missing_model_raises
    assert_raises(ArgumentError) do
      FullSearch.multi_search(
        query: "test",
        groups: [
          {key: :bad, label: "Bad"}
        ]
      )
    end
  end

  def test_raises_when_model_not_configured
    unconfigured = Class.new(Customer)
    unconfigured.table_name = "customers"
    assert_raises(FullSearch::NotConfiguredError) do
      FullSearch.multi_search(
        query: "Sam",
        groups: [{key: :bad, model: unconfigured}]
      )
    end
  end

  def test_highlight_option
    account = Account.create!(name: "Acme")
    @customer_model.create!(account_id: account.id, first_name: "Arthur")
    FullSearch::Index.rebuild!(@customer_model)
    result = FullSearch.multi_search(
      query: "Arthur",
      groups: [{key: :customers, model: @customer_model, filters: {account_id: account.id}, highlight: true}]
    )
    record = result[:groups].first[:results].first
    assert record.respond_to?(:full_search_snippet)
    assert_includes record.full_search_snippet, "<mark>"
  end

  def test_highlight_fields_option
    account = Account.create!(name: "Acme")
    @customer_model.create!(account_id: account.id, first_name: "Arthur")
    FullSearch::Index.rebuild!(@customer_model)

    result = FullSearch.multi_search(
      query: "Arthur",
      groups: [
        {key: :customers, label: "Customers", model: @customer_model,
         filters: {account_id: account.id}, highlight_fields: true}
      ]
    )

    record = result[:groups].first[:results].first
    assert record.respond_to?(:full_search_highlight_fields)
    assert_includes record.full_search_highlight_fields["first_name"], "<mark>"
  end

  def test_applies_includes_to_avoid_n_plus_one
    account = Account.create!(name: "Acme")
    customer = Customer.create!(account_id: account.id, first_name: "Sam")
    @vehicle_model = Class.new(Vehicle) do
      full_search do
        field :make, weight: 5
        filter :account_id, required: true
      end
    end
    @vehicle_model.table_name = "vehicles"
    @vehicle_model.create!(account_id: account.id, make: "Honda", customer_id: customer.id)
    FullSearch::Index.rebuild!(@vehicle_model)

    query_count = 0
    callback = ->(*) { query_count += 1 }

    result = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      result = FullSearch.multi_search(
        query: "Honda",
        groups: [
          {key: :vehicles, label: "Vehicles", model: @vehicle_model,
           filters: {account_id: account.id}, includes: [:customer]}
        ]
      )
      result[:groups].first[:results].first.customer.full_name
    end

    assert_equal "Sam", result[:groups].first[:results].first.customer.full_name
    assert query_count <= 6, "Expected at most 6 queries with includes, got #{query_count}"
  ensure
    FullSearch::Index.drop!(@vehicle_model) if @vehicle_model
    Vehicle.delete_all
  end

  def test_applies_scope_before_materializing
    account = Account.create!(name: "Acme")
    @customer_model.create!(account_id: account.id, first_name: "Sam", last_name: "Smith")
    FullSearch::Index.rebuild!(@customer_model)

    called = false
    result = FullSearch.multi_search(
      query: "Sam",
      groups: [
        {key: :customers, label: "Customers", model: @customer_model,
         filters: {account_id: account.id},
         scope: ->(rel) {
           called = true
           rel.where(last_name: "Smith")
         }}
      ]
    )

    assert called
    assert_equal 1, result[:total_count]
  end

  def test_applies_per_strategy_limit
    account = Account.create!(name: "Acme")
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
        typo_tolerance
      end
    end
    model.table_name = "customers"
    20.times { model.create!(account_id: account.id, first_name: "Smyth") }
    FullSearch::Index.rebuild!(model)

    result = FullSearch.multi_search(
      query: "Smith",
      groups: [
        {key: :customers, label: "Customers", model: model,
         filters: {account_id: account.id}, limit: 8, per_strategy_limit: 5}
      ]
    )

    group = result[:groups].first
    assert group[:results].size <= 5
  end
end
