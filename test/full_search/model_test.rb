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

    results = @model.full_search("Sam", filters: {account_id: 1})
    assert_kind_of ActiveRecord::Relation, results
    assert_includes results.to_a, customer
  end

  def test_search_is_alias_for_full_search
    customer = @model.create!(account_id: 1, first_name: "Sam")
    FullSearch::Index.rebuild!(@model)

    results = @model.search("Sam", filters: {account_id: 1})
    assert_kind_of ActiveRecord::Relation, results
    assert_includes results.to_a, customer
  end

  def test_search_does_not_override_existing_search_method
    klass = Class.new(Customer) do
      def self.search(*)
        :custom_search
      end

      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
      end
    end
    klass.table_name = "customers"

    assert_equal :custom_search, klass.search("anything", filters: {account_id: 1})
  end

  def test_full_search_still_works_when_search_is_overridden
    klass = Class.new(Customer) do
      def self.search(*)
        :custom_search
      end

      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
      end
    end
    klass.table_name = "customers"

    customer = klass.create!(account_id: 1, first_name: "Sam")
    FullSearch::Index.rebuild!(klass)

    results = klass.full_search("Sam", filters: {account_id: 1})
    assert_kind_of ActiveRecord::Relation, results
    assert_includes results.to_a, customer
  end

  def test_full_search_defers_setup_until_after_class_is_defined
    klass = Class.new(Customer) do
      self.table_name = "customers"

      full_search do
        field :computed, source: -> { computed_value }
      end

      def computed_value
        "hello"
      end
    end

    assert_kind_of FullSearch::Dsl, klass.full_search_dsl

    FullSearch::Index.rebuild!(klass)
    record = klass.create!(account_id: 1, first_name: "Sam")
    assert_equal "hello", record.full_search_text_for(:computed)
  end

  def test_source_block_error_includes_field_context
    field = FullSearch::Dsl::Field.new(name: "bad", weight: 1, source: -> { missing_method }, reindex_on: nil, async: false, as: nil, version: nil)
    record = Customer.new(account_id: 1, first_name: "Sam")

    error = assert_raises(NameError) do
      FullSearch::Model.evaluate_source(record, field)
    end
    assert_includes error.message, "field \"bad\""
    assert_includes error.message, "missing_method"
  end
end
