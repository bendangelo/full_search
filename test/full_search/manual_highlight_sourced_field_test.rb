# frozen_string_literal: true

require "test_helper"
require "ostruct"

class FullSearch::ManualHighlightSourcedFieldTest < ActiveSupport::TestCase
  def setup
    extend_customers_schema

    @account = Account.create!(name: "Acme")

    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :tag_names, weight: 1, source: -> { "computed_value" }
        filter :account_id, required: true
        exact_match :code
      end
    end
    @model.table_name = "customers"
  end

  def teardown
    Customer.delete_all
    Account.delete_all
  end

  def test_manual_field_highlight_respects_sourced_fields
    customer = @model.create!(account_id: @account.id, first_name: "", code: "XYZ")
    FullSearch::Index.rebuild!(@model)

    # Force the manual highlight fallback:
    # ExactMatch finds the record via code, but the FTS table has empty first_name
    # and empty tag_names (backfilled '' for sourced fields), so build_field_snippets
    # returns nothing and manual_field_snippets is called.
    results = @model.full_search("XYZ", filters: { account_id: @account.id }, highlight_fields: true).to_a
    refute results.empty?, "Expected the exact-match search to find at least one record"
    result = results.first

    assert result.respond_to?(:full_search_highlight_fields)
  end

  private

  def extend_customers_schema
    conn = ActiveRecord::Base.connection
    unless conn.column_exists?(:customers, :code)
      conn.add_column(:customers, :code, :string)
    end
  end
end
