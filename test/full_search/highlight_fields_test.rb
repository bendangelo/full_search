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
end
