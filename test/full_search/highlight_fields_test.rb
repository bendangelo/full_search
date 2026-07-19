# frozen_string_literal: true

require "test_helper"

class FullSearch::HighlightFieldsTest < ActiveSupport::TestCase
  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        highlight
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"
    @account = Account.create!(name: "Acme")
  end

  def teardown
    Customer.delete_all
  end

  def test_returns_hash_per_field
    @model.create!(account_id: @account.id, first_name: "Samantha", last_name: "Smith")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("Samantha", filters: { account_id: @account.id }, highlight_fields: true).to_a
    result = results.first

    assert result.respond_to?(:full_search_highlight_fields)
    assert_includes result.full_search_highlight_fields["first_name"], "<mark>"
  end

  def test_omits_fields_without_hits
    @model.create!(account_id: @account.id, first_name: "Samantha", last_name: "Smith")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("Samantha", filters: { account_id: @account.id }, highlight_fields: true).to_a
    result = results.first

    assert_nil result.full_search_highlight_fields["last_name"]
  end

  def test_highlight_fields_with_short_prefix_via_trigram
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        highlight
        filter :account_id, required: true
        tokenize "trigram"
        typo_tolerance
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Sarah", last_name: "Jones")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("sar", filters: { account_id: account.id }, highlight_fields: true).to_a
    result = results.first

    assert result.respond_to?(:full_search_highlight_fields)
    assert_includes result.full_search_highlight_fields["first_name"], "<mark>"
    assert_includes result.full_search_highlight_fields["first_name"], "Sar"
    assert_nil result.full_search_highlight_fields["last_name"]
  end

  def test_alias_keys_highlight_fields
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5, as: :fname
        field :last_name, weight: 5
        highlight
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Samantha", last_name: "Smith")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("Samantha", filters: { account_id: account.id }, highlight_fields: true).to_a
    result = results.first

    assert result.respond_to?(:full_search_highlight_fields)
    refute_includes result.full_search_highlight_fields.keys, "first_name",
      "highlight keys should use alias, not internal name"
    assert_includes result.full_search_highlight_fields.keys, "fname",
      "highlight keys should use alias"
    assert_includes result.full_search_highlight_fields["fname"], "<mark>"
    assert_nil result.full_search_highlight_fields["last_name"]
  end

  def test_short_prefix_via_like_fallback_highlights_matched_substring
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        highlight
        filter :account_id, required: true
        tokenize "trigram"
        typo_tolerance
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Sarah", last_name: "Jones")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("sa", filters: { account_id: account.id }, highlight_fields: true).to_a
    result = results.first

    assert result, "Expected a prefix match for sa"
    assert_includes result.full_search_highlight_fields["first_name"], "<mark>",
      "Expected prefix match to produce a highlight"
    assert_includes result.full_search_highlight_fields["first_name"], "Sa",
      "Expected prefix highlight to include the matched prefix"
  end
end
