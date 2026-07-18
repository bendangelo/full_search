# frozen_string_literal: true

require "test_helper"

class FullSearch::SearchTest < ActiveSupport::TestCase
  def setup
    @customer_model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
      end
    end
    @customer_model.table_name = "customers"
    FullSearch::Index.rebuild!(@customer_model)
  end

  def teardown
    Customer.delete_all
  end

  def test_full_search_finds_by_prefix
    account = Account.create!(name: "Acme")
    customer = @customer_model.create!(account_id: account.id, first_name: "Sammy")
    FullSearch::Index.rebuild!(@customer_model)

    results = @customer_model.full_search("Sam", filters: { account_id: account.id })
    assert_includes results.to_a, customer
  end

  def test_missing_required_filter_raises
    assert_raises(FullSearch::MissingRequiredFilterError) do
      @customer_model.full_search("Sam", filters: {})
    end
  end
end
