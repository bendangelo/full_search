# frozen_string_literal: true

require "test_helper"

class FullSearch::HighlighterTest < ActiveSupport::TestCase
  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
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

  def test_adds_snippet_attribute
    @model.create!(account_id: @account.id, first_name: "Samantha")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("Samantha", filters: {account_id: @account.id}, highlight: true).to_a
    result = results.first
    assert result.respond_to?(:full_search_snippet)
    assert result.full_search_snippet.include?("<mark>")
  end

  def test_custom_highlight_tags
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        highlight open_tag: "[", close_tag: "]"
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Samantha")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("Samantha", filters: {account_id: account.id}, highlight: true).to_a
    result = results.first
    assert_includes result.full_search_snippet, "[Samantha]"
  end

  def test_highlight_fields_with_custom_tags
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        highlight open_tag: "**", close_tag: "**"
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Samantha")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("Samantha", filters: {account_id: account.id}, highlight_fields: true).to_a
    result = results.first
    assert_includes result.full_search_highlight_fields["first_name"], "**Samantha**"
  end

  def test_snippet_with_short_prefix_via_trigram
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        highlight
        filter :account_id, required: true
        tokenize "trigram"
        typo_tolerance
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("sar", filters: {account_id: account.id}, highlight: true).to_a
    result = results.first
    assert result.respond_to?(:full_search_snippet)
    assert result.full_search_snippet.include?("<mark>")
    assert result.full_search_snippet.include?("Sar")
  end
end
