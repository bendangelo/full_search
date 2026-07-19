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

  def test_full_search_finds_by_short_prefix
    account = Account.create!(name: "Acme")
    customer = @customer_model.create!(account_id: account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(@customer_model)

    results = @customer_model.full_search("sa", filters: { account_id: account.id })
    assert_includes results.to_a, customer
  end

  def test_full_search_finds_by_short_prefix_with_porter
    account = Account.create!(name: "Acme")
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
        tokenize "porter"
      end
    end
    model.table_name = "customers"
    customer = model.create!(account_id: account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("sa", filters: { account_id: account.id })
    assert_includes results.to_a, customer
  end

  def test_full_search_finds_by_short_prefix_with_trigram
    account = Account.create!(name: "Acme")
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
        typo_tolerance
      end
    end
    model.table_name = "customers"
    customer = model.create!(account_id: account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("sa", filters: { account_id: account.id })
    assert_includes results.to_a, customer
  end

  def test_short_prefix_with_trigram_tokenizer_falls_back_to_like
    account = Account.create!(name: "Acme")
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
        tokenize "trigram"
        typo_tolerance
      end
    end
    model.table_name = "customers"
    customer = model.create!(account_id: account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("sa", filters: { account_id: account.id })
    assert_includes results.to_a, customer
  end

  def test_missing_required_filter_raises
    assert_raises(FullSearch::MissingRequiredFilterError) do
      @customer_model.full_search("Sam", filters: {})
    end
  end

  def test_offset_and_limit
    account = Account.create!(name: "Acme")
    5.times { |i| @customer_model.create!(account_id: account.id, first_name: "Person #{i}") }
    FullSearch::Index.rebuild!(@customer_model)

    first_page = @customer_model.full_search("Person", filters: { account_id: account.id }, limit: 2, offset: 0)
    assert_equal 2, first_page.size

    second_page = @customer_model.full_search("Person", filters: { account_id: account.id }, limit: 2, offset: 2)
    assert_equal 2, second_page.size
  end

  def test_empty_query_returns_none
    account = Account.create!(name: "Acme")
    @customer_model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(@customer_model)

    results = @customer_model.full_search("", filters: { account_id: account.id })
    assert_equal 0, results.size
    assert_kind_of ActiveRecord::Relation, results
  end

  def test_highlight_returns_array
    account = Account.create!(name: "Acme")
    @customer_model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(@customer_model)

    results = @customer_model.full_search("Sam", filters: { account_id: account.id }, highlight: true)
    assert_kind_of Array, results
  end
end
