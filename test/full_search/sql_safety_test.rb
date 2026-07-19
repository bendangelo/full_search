# frozen_string_literal: true

require "test_helper"

class FullSearch::SqlSafetyTest < ActiveSupport::TestCase
  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"
  end

  def teardown
    Customer.delete_all
    Account.delete_all
  end

  def test_malicious_filter_key_is_rejected
    account = Account.create!(name: "Acme")
    @model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(@model)

    assert_raises(FullSearch::MissingRequiredFilterError) do
      @model.full_search("Sam", filters: {"account_id; DROP TABLE customers; --" => account.id})
    end
  end

  def test_rank_direction_is_whitelisted
    model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
        rank_by :created_at, :asc
      end
    end
    model.table_name = "customers"
    assert_kind_of Array, model.full_search_dsl.rank_bys
  end

  def test_invalid_rank_direction_raises
    assert_raises(FullSearch::InvalidFieldError) do
      Class.new(Customer) do
        full_search do
          field :first_name
          filter :account_id, required: true
          rank_by :created_at, "DESC; DROP TABLE customers; --"
        end
      end
    end
  end
end
