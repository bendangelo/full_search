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
end
