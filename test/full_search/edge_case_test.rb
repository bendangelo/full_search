# frozen_string_literal: true

require "test_helper"

class FullSearch::EdgeCaseTest < ActiveSupport::TestCase
  def test_empty_source_returns_blank
    model = Class.new(Customer) do
      full_search do
        field :computed, source: -> {}
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    FullSearch::Index.rebuild!(model)
    record = model.create!(account_id: account.id, first_name: "Sam")

    row = ActiveRecord::Base.connection.execute(
      "SELECT computed FROM #{FullSearch::Index.fts_table_name(model)} WHERE rowid = #{ActiveRecord::Base.connection.quote(record.id)}"
    ).first
    assert_equal "", row["computed"]
  end

  def test_long_query_raises
    model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"

    assert_raises(FullSearch::InvalidQueryError) do
      model.full_search("a" * 500, filters: {account_id: 1})
    end
  end

  def test_null_byte_query_raises
    model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"

    assert_raises(FullSearch::InvalidQueryError) do
      model.full_search("foo\0bar", filters: {account_id: 1})
    end
  end

  def test_empty_query_returns_none
    model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("", filters: {account_id: account.id})
    assert_equal 0, results.size
    assert_kind_of ActiveRecord::Relation, results
  end

  def test_nil_query_returns_none
    model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(model)

    results = model.full_search(nil, filters: {account_id: account.id})
    assert_equal 0, results.size
  end
end
