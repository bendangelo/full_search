# frozen_string_literal: true

require "test_helper"

class FullSearch::OnceRebuiltTest < ActiveSupport::TestCase
  include FullSearch::TestHelpers

  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :display_name, weight: 5, source: -> { "#{first_name} #{last_name}".strip }
        filter :account_id, required: true
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
    FullSearch.deregister_model(@model)
    FullSearch::OnceRebuilt.clear!
  end

  def test_rebuilds_models_on_first_call
    once_full_search_rebuilt(@model)
    assert FullSearch::Index.send(:table_exists?, @model)
  end

  def test_skips_rebuild_on_subsequent_calls
    account = Account.create!(name: "Acme")

    once_full_search_rebuilt(@model)
    record = @model.create!(account_id: account.id, first_name: "Sam", last_name: "Smith")
    results = @model.full_search("Sam", filters: {account_id: account.id}).to_a
    assert_includes results, record

    once_full_search_rebuilt(@model)
    results = @model.full_search("Sam", filters: {account_id: account.id}).to_a
    assert_includes results, record
    assert FullSearch::Index.send(:table_exists?, @model)
  end

  def test_uses_empty_models_when_no_arguments
    FullSearch.register_model(@model)
    FullSearch::OnceRebuilt.clear!
    once_full_search_rebuilt(@model)
    assert FullSearch::Index.send(:table_exists?, @model)
  ensure
    FullSearch.deregister_model(@model)
  end
end
