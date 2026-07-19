# frozen_string_literal: true

require "test_helper"

class FullSearch::ExactMatchHighlightTest < ActiveSupport::TestCase
  def setup
    clean_fts_tables!
    @account = Account.create!(name: "Acme")
  end

  def teardown
    FullSearch::Index.drop!(@model) rescue nil
    Customer.delete_all
    Account.delete_all
    clean_fts_tables!
  end

  def test_exact_match_field_appears_in_highlight_fields
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
        exact_match :company_name
        highlight
      end
    end
    @model.table_name = "customers"

    @model.create!(account_id: @account.id, first_name: "Sam", company_name: "ABC Corp")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("ABC Corp", filters: { account_id: @account.id }, highlight_fields: true).to_a
    refute results.empty?
    result = results.first

    assert result.respond_to?(:full_search_highlight_fields)
    assert_includes result.full_search_highlight_fields["company_name"], "<mark>"
  end

  def test_exact_match_highlight_with_source_proc
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
        exact_match :company_name, source: -> { company_name&.upcase }
        highlight
      end
    end
    @model.table_name = "customers"

    @model.create!(account_id: @account.id, first_name: "Sam", company_name: "ABC CORP")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("abc corp", filters: { account_id: @account.id }, highlight_fields: true).to_a
    refute results.empty?
    result = results.first

    assert_includes result.full_search_highlight_fields["company_name"], "<mark>"
  end

  private

  def clean_fts_tables!
    ActiveRecord::Base.connection.execute(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE '%_fts%'"
    ).each { |r| ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS #{r['name']}") }
    ActiveRecord::Base.connection.execute(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_fts%'"
    ).each { |r| ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS #{r['name']}") }
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS full_search_index_versions")
  end
end
