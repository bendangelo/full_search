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

    assert_raises(FullSearch::UnknownFilterError) do
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

  def test_index_if_sql_with_semicolon_raises
    dsl = FullSearch::Dsl.new(Customer)
    error = assert_raises(FullSearch::InvalidFieldError) do
      dsl.index_if(sql: "status = 1; DROP TABLE customers")
    end
    assert_includes error.message, "Customer"
    assert_includes error.message, "index_if"
  end

  def test_exact_match_sql_with_comment_raises
    dsl = FullSearch::Dsl.new(Customer)
    error = assert_raises(FullSearch::InvalidFieldError) do
      dsl.exact_match :vin, sql: "vin /* dangerous */"
    end
    assert_includes error.message, "Customer"
    assert_includes error.message, "exact_match"
  end

  def test_valid_index_if_sql_accepted
    dsl = FullSearch::Dsl.new(Customer)
    dsl.index_if(sql: "active = 1 AND deleted_at IS NULL")
    assert_equal "active = 1 AND deleted_at IS NULL", dsl.index_if_sql
  end

  def test_valid_exact_match_sql_accepted
    dsl = FullSearch::Dsl.new(Customer)
    dsl.exact_match :vin, sql: "UPPER(REPLACE(col, '-', ''))"
    assert_equal "UPPER(REPLACE(col, '-', ''))", dsl.exact_matches.first.sql
  end
end
