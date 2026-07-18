# frozen_string_literal: true

require "test_helper"

class FullSearch::ModelTest < ActiveSupport::TestCase
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
  end

  def test_full_search_macro_registers_dsl
    klass = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
      end
    end

    assert_kind_of FullSearch::Dsl, klass.full_search_dsl
    assert_equal "first_name", klass.full_search_dsl.fields.first.name
  end

  def test_full_search_returns_relation
    customer = @model.create!(account_id: 1, first_name: "Sam")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("Sam", filters: { account_id: 1 })
    assert_kind_of ActiveRecord::Relation, results
    assert_includes results.to_a, customer
  end
end
