# frozen_string_literal: true

require "test_helper"

class FullSearch::RankByTest < ActiveSupport::TestCase
  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
        rank_by :updated_at, :desc
      end
    end
    @model.table_name = "customers"
    @account = Account.create!(name: "Acme")
  end

  def teardown
    Customer.delete_all
  end

  def test_orders_by_updated_at_when_query_matches_multiple
    old_record = @model.create!(account_id: @account.id, first_name: "Sam", updated_at: 1.day.ago)
    new_record = @model.create!(account_id: @account.id, first_name: "Sam", updated_at: 1.hour.ago)
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("Sam", filters: { account_id: @account.id }).to_a
    assert_equal [new_record, old_record], results
  end

  def test_boosts_exact_match_to_top
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        exact_match :first_name
        filter :account_id, required: true
        rank_by :updated_at, :desc
      end
    end
    @model.table_name = "customers"

    exact = @model.create!(account_id: @account.id, first_name: "ExactSam", updated_at: 1.day.ago)
    partial = @model.create!(account_id: @account.id, first_name: "Samuel", updated_at: 1.hour.ago)
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("ExactSam", filters: { account_id: @account.id }).to_a
    assert_equal exact, results.first
  end
end
