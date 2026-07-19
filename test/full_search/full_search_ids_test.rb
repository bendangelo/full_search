# frozen_string_literal: true

require "test_helper"

class FullSearch::FullSearchIdsTest < ActiveSupport::TestCase
  def test_returns_ids
    model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    customer = model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(model)
    ids = model.full_search_ids("Sam", filters: { account_id: account.id })
    assert_includes ids, customer.id
  end
end
