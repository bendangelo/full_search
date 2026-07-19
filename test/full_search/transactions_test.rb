# frozen_string_literal: true

require "test_helper"

class FullSearch::TransactionsTest < ActiveSupport::TestCase
  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"
    FullSearch::Index.rebuild!(@model)
    @account = Account.create!(name: "Acme")
  end

  def teardown
    Customer.delete_all
    Account.delete_all
    FullSearch::Index.drop!(@model) rescue nil
  end

  def test_insert_inside_transaction_is_indexed
    customer = nil
    ActiveRecord::Base.transaction do
      customer = @model.create!(account_id: @account.id, first_name: "Sam")
    end
    results = @model.full_search("Sam", filters: { account_id: @account.id })
    assert_includes results.to_a, customer
  end

  def test_rolled_back_insert_is_not_indexed
    ActiveRecord::Base.transaction do
      @model.create!(account_id: @account.id, first_name: "Sam")
      raise ActiveRecord::Rollback
    end
    results = @model.full_search("Sam", filters: { account_id: @account.id })
    assert_empty results.to_a
  end
end
