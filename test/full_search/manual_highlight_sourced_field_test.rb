# frozen_string_literal: true

require "test_helper"
require "ostruct"

class FullSearch::ManualHighlightSourcedFieldTest < ActiveSupport::TestCase
  def setup
    clean_fts_tables!
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
    begin
      FullSearch::Index.drop!(@model)
    rescue
      nil
    end
    Customer.delete_all
    Account.delete_all
  end

  def test_manual_field_highlight_respects_sourced_fields
    @model.create!(account_id: @account.id, first_name: "", code: "XYZ")
    FullSearch::Index.rebuild!(@model)

    # Force the manual highlight fallback:
    # ExactMatch finds the record via code, but the FTS table has empty first_name
    # and empty tag_names (backfilled '' for sourced fields), so build_field_snippets
    # returns nothing and manual_field_snippets is called.
    results = @model.full_search("XYZ", filters: {account_id: @account.id}, highlight_fields: true).to_a
    refute results.empty?, "Expected the exact-match search to find at least one record"
    result = results.first

    assert result.respond_to?(:full_search_highlight_fields)
    # FTS doesn't match (first_name is empty), manual fallback also empty, but
    # exact_match on :code finds and highlights the field
    assert_includes result.full_search_highlight_fields["code"], "<mark>"
    assert_nil result.full_search_highlight_fields["first_name"]
    assert_nil result.full_search_highlight_fields["tag_names"]
  end

  def test_manual_highlight_with_source_proc
    @model.create!(account_id: @account.id, first_name: "Alice", code: "ABC")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("ABC", filters: {account_id: @account.id}, highlight_fields: true).to_a
    refute results.empty?
    result = results.first

    # FTS has empty tag_names (sourced field backfilled as ''), so manual fallback runs
    # tag_names source returns "computed_value" which doesn't match "ABC"
    assert_nil result.full_search_highlight_fields["tag_names"]

    # first_name is empty string in this record, manual fallback omits it
    assert_nil result.full_search_highlight_fields["first_name"]
  end

  private

  def clean_fts_tables!
    ActiveRecord::Base.connection.execute(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE '%_fts%'"
    ).each { |r| ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS #{r["name"]}") }
    ActiveRecord::Base.connection.execute(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_fts%'"
    ).each { |r| ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS #{r["name"]}") }
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS full_search_index_versions")
  end

  def extend_customers_schema
    conn = ActiveRecord::Base.connection
    unless conn.column_exists?(:customers, :code)
      conn.add_column(:customers, :code, :string)
      Customer.reset_column_information
    end
  end
end
