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
    customer = @model.create!(account_id: @account.id, first_name: "Samantha")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("Samantha", filters: { account_id: @account.id }, highlight: true).to_a
    result = results.first
    assert result.respond_to?(:full_search_snippet)
    assert result.full_search_snippet.include?("<mark>")
  end
end
