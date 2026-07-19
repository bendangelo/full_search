# frozen_string_literal: true

require "test_helper"

class FullSearch::TypoTest < ActiveSupport::TestCase
  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        typo_tolerance
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"
    @account = Account.create!(name: "Acme")
  end

  def teardown
    Customer.delete_all
  end

  def test_typo_tolerance_flag
    assert @model.full_search_dsl.typo_tolerance?
    assert_equal 3, @model.full_search_dsl.typo_tolerance_min_term_length
  end

  def test_trigram_fallback_finds_substring
    customer = @model.create!(account_id: @account.id, first_name: "Samantha")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("antha", filters: { account_id: @account.id })
    assert_includes results.to_a, customer
  end

  def test_trigram_fallback_finds_one_typo
    customer = @model.create!(account_id: @account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("sarh", filters: { account_id: @account.id })
    assert_includes results.to_a, customer
  end

  def test_no_fallback_when_disabled
    model_without = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
      end
    end
    model_without.table_name = "customers"
    customer = model_without.create!(account_id: @account.id, first_name: "Samantha")
    FullSearch::Index.rebuild!(model_without)

    results = model_without.full_search("antha", filters: { account_id: @account.id })
    refute_includes results.to_a, customer
  end

  def test_min_term_length_option
    @model.full_search_dsl.typo_tolerance(true, min_term_length: 5)
    assert_equal 5, @model.full_search_dsl.typo_tolerance_min_term_length
  end

  def test_one_typo_at_min_size
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
        typo_tolerance(min_term_length: 5)
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")

    model.create!(account_id: account.id, first_name: "Rings")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("Rnigs", filters: { account_id: account.id })
    assert_equal 1, results.size
  end

  def test_no_one_typo_below_min_size
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
        typo_tolerance(min_term_length: 5)
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")

    model.create!(account_id: account.id, first_name: "Lord")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("Lrod", filters: { account_id: account.id })
    assert_equal 0, results.size
  end

  def test_two_typos_at_min_size
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
        typo_tolerance(min_term_length: 5)
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")

    model.create!(account_id: account.id, first_name: "Frankenstein")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("Farnkenstien", filters: { account_id: account.id })
    assert_equal 1, results.size
  end

  def test_no_two_typos_below_min_size
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
        typo_tolerance(min_term_length: 5)
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")

    model.create!(account_id: account.id, first_name: "Dracula")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("Darclua", filters: { account_id: account.id })
    assert_equal 0, results.size
  end

  def test_no_typo_with_matching_strategy_all
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
        typo_tolerance(min_term_length: 3)
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")

    model.create!(account_id: account.id, first_name: "Harry", last_name: "Potter")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("harry pottr", filters: { account_id: account.id }, matching_strategy: "all")
    assert_equal 0, results.size
  end

  def test_typo_match_highlight_fields
    customer = @model.create!(account_id: @account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("sarh", filters: { account_id: @account.id }, highlight_fields: true).to_a
    result = results.first

    assert result, "Expected a fuzzy match for sarh"
    assert_includes result.full_search_highlight_fields["first_name"], "<mark>",
      "Expected fuzzy match to produce a highlight"
    assert_includes result.full_search_highlight_fields["first_name"], "Sar",
      "Expected fuzzy highlight to include the corrected text"
  end
end
