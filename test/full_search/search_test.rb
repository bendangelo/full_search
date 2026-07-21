# frozen_string_literal: true

require "test_helper"

class FullSearch::SearchTest < ActiveSupport::TestCase
  def setup
    @customer_model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
      end
    end
    @customer_model.table_name = "customers"
    FullSearch::Index.rebuild!(@customer_model)
  end

  def teardown
    Customer.delete_all
  end

  def test_full_search_finds_by_prefix
    account = Account.create!(name: "Acme")
    customer = @customer_model.create!(account_id: account.id, first_name: "Sammy")
    FullSearch::Index.rebuild!(@customer_model)

    results = @customer_model.full_search("Sam", filters: {account_id: account.id})
    assert_includes results.to_a, customer
  end

  def test_full_search_finds_by_short_prefix
    account = Account.create!(name: "Acme")
    customer = @customer_model.create!(account_id: account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(@customer_model)

    results = @customer_model.full_search("sa", filters: {account_id: account.id})
    assert_includes results.to_a, customer
  end

  def test_full_search_finds_by_short_prefix_with_porter
    account = Account.create!(name: "Acme")
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
        tokenize "porter"
      end
    end
    model.table_name = "customers"
    customer = model.create!(account_id: account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("sa", filters: {account_id: account.id})
    assert_includes results.to_a, customer
  end

  def test_full_search_finds_by_short_prefix_with_trigram
    account = Account.create!(name: "Acme")
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
        typo_tolerance
      end
    end
    model.table_name = "customers"
    customer = model.create!(account_id: account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("sa", filters: {account_id: account.id})
    assert_includes results.to_a, customer
  end

  def test_short_prefix_with_trigram_tokenizer_and_typo_tolerance
    account = Account.create!(name: "Acme")
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
        tokenize "trigram"
        typo_tolerance
        min_like_prefix_length 2
      end
    end
    model.table_name = "customers"
    model.create!(account_id: account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(model)

    results = model.full_search("sa", filters: {account_id: account.id})
    assert_not_empty results
    assert_equal "Sarah", results.first.first_name
  end

  def test_missing_required_filter_raises
    assert_raises(FullSearch::MissingRequiredFilterError) do
      @customer_model.full_search("Sam", filters: {})
    end
  end

  def test_offset_and_limit
    account = Account.create!(name: "Acme")
    5.times { |i| @customer_model.create!(account_id: account.id, first_name: "Person #{i}") }
    FullSearch::Index.rebuild!(@customer_model)

    first_page = @customer_model.full_search("Person", filters: {account_id: account.id}, limit: 2, offset: 0)
    assert_equal 2, first_page.size

    second_page = @customer_model.full_search("Person", filters: {account_id: account.id}, limit: 2, offset: 2)
    assert_equal 2, second_page.size
  end

  def test_empty_query_returns_none
    account = Account.create!(name: "Acme")
    @customer_model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(@customer_model)

    results = @customer_model.full_search("", filters: {account_id: account.id})
    assert_equal 0, results.size
    assert_kind_of ActiveRecord::Relation, results
  end

  def test_highlight_returns_array
    account = Account.create!(name: "Acme")
    @customer_model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(@customer_model)

    results = @customer_model.full_search("Sam", filters: {account_id: account.id}, highlight: true)
    assert_kind_of Array, results
  end

  def test_required_filter_accepts_string_keys
    account = Account.create!(name: "Acme")
    customer = @customer_model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(@customer_model)
    results = @customer_model.full_search("Sam", filters: {"account_id" => account.id})
    assert_includes results.to_a, customer
  end

  def test_stale_config_raises_error
    model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(model)

    ActiveRecord::Base.connection.execute(
      "UPDATE full_search_index_versions SET config_hash = 'fakehash' WHERE table_name = 'customers'"
    )

    assert_raises(FullSearch::ConfigChangedError) do
      model.full_search("Sam", filters: {account_id: account.id})
    end
  end

  def test_stale_config_logs_warning_when_configured
    original_behavior = FullSearch.config.stale_query_behavior
    FullSearch.config.stale_query_behavior = :log_and_fallback

    log_string = StringIO.new
    Rails.define_singleton_method(:logger) { Logger.new(log_string) } unless Rails.respond_to?(:logger)

    model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(model)

    ActiveRecord::Base.connection.execute(
      "UPDATE full_search_index_versions SET config_hash = 'fakehash' WHERE table_name = 'customers'"
    )

    assert_nothing_raised do
      results = model.full_search("Sam", filters: {account_id: account.id})
      assert_not_empty results
    end

    assert_match(/stale/i, log_string.string)
  ensure
    FullSearch.config.stale_query_behavior = original_behavior
  end

  def test_stale_config_auto_rebuilds_when_configured
    original = FullSearch.config.auto_rebuild_on_stale_query
    FullSearch.config.auto_rebuild_on_stale_query = true

    model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    customer = model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(model)

    ActiveRecord::Base.connection.execute(
      "UPDATE full_search_index_versions SET config_hash = 'fakehash' WHERE table_name = 'customers'"
    )

    assert_nothing_raised do
      results = model.full_search("Sam", filters: {account_id: account.id})
      assert_includes results.to_a, customer
    end
  ensure
    FullSearch.config.auto_rebuild_on_stale_query = original
  end

  def test_no_stored_config_does_not_raise
    ActiveRecord::Base.connection.execute(
      "DELETE FROM full_search_index_versions WHERE table_name = 'customers'"
    )

    model = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Sam")

    assert_nothing_raised do
      model.full_search("Sam", filters: {account_id: account.id})
    end
  end

  def test_nil_filter_values
    account = Account.create!(name: "Acme")
    @customer_model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(@customer_model)
    results = @customer_model.full_search("Sam", filters: {account_id: nil})
    assert_empty results.to_a
  end

  def test_highlighter_restricts_to_returned_record_ids
    account = Account.create!(name: "Acme")
    10.times { |i| @customer_model.create!(account_id: account.id, first_name: "Sam#{i}") }
    FullSearch::Index.rebuild!(@customer_model)

    results = @customer_model.full_search(
      "Sam",
      filters: {account_id: account.id},
      limit: 2,
      highlight_fields: true,
      per_strategy_limit: 2
    )

    assert_equal 2, results.size
    results.each do |record|
      assert record.full_search_highlight_fields.key?("first_name")
      assert_includes record.full_search_highlight_fields["first_name"], "<mark>"
    end
  end

  def test_fuzzy_respects_per_strategy_limit
    account = Account.create!(name: "Acme")
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
        typo_tolerance
        rank_by :updated_at, :desc
      end
    end
    model.table_name = "customers"
    20.times do |i|
      model.create!(account_id: account.id, first_name: "Smyth", last_name: "Doe", updated_at: Time.current - i.seconds)
    end
    FullSearch::Index.rebuild!(model)

    results = model.full_search(
      "Smith",
      filters: {account_id: account.id},
      per_strategy_limit: 5
    )

    assert results.to_a.size <= 5
  end

  def test_short_query_skips_like_prefix_fallback
    account = Account.create!(name: "Acme")
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
        typo_tolerance
        min_like_prefix_length 3
      end
    end
    model.table_name = "customers"
    5.times { |i| model.create!(account_id: account.id, first_name: "bx#{i}") }
    FullSearch::Index.rebuild!(model)

    like_queries = []
    callback = ->(name, started, finished, unique_id, payload) {
      like_queries << payload[:sql] if payload[:sql]&.include?("LIKE")
    }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      result = model.full_search("bx", filters: {account_id: account.id}, per_strategy_limit: 50)
      assert result.any?
    end

    assert like_queries.none? { |sql| sql.include?("first_name LIKE") }
  end

  def test_raises_missing_table_error_when_fts_table_does_not_exist
    FullSearch::Index.drop!(@customer_model)
    assert FullSearch::Index.missing_table?(@customer_model)

    account = Account.create!(name: "Acme")
    @customer_model.create!(account_id: account.id, first_name: "Sammy")

    assert_raises(FullSearch::MissingTableError) do
      @customer_model.full_search("Sam", filters: {account_id: account.id})
    end
  ensure
    FullSearch::Index.rebuild!(@customer_model)
  end
end
