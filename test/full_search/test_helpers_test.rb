# frozen_string_literal: true

require "test_helper"

class FullSearch::TestHelpersTest < ActiveSupport::TestCase
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
  end

  def test_rebuild_creates_index
    rebuild_full_search_index(@model)
    assert FullSearch::Index.send(:table_exists?, @model)
  end

  def test_rebuild_accepts_string_class_name
    Object.const_set(:TestHelpersSearchableCustomer, @model)

    rebuild_full_search_index("TestHelpersSearchableCustomer")
    assert FullSearch::Index.send(:table_exists?, @model)
  ensure
    Object.send(:remove_const, :TestHelpersSearchableCustomer)
  end

  def test_reindex_refreshes_source_fields
    account = Account.create!(name: "Acme")
    record = @model.new(account_id: account.id, first_name: "Sam", last_name: "Smith")
    rebuild_full_search_index(@model)
    record.save!

    record.update!(first_name: "Samantha")
    reindex_full_search(@model)

    results = @model.full_search("Samantha", filters: {account_id: account.id})
    assert_includes results.to_a, record
  end

  def test_reset_rebuilds_given_models
    model_two = Class.new(Account) do
      full_search do
        field :name, weight: 5
      end
    end
    model_two.table_name = "accounts"

    reset_full_search!(@model, model_two)

    assert FullSearch::Index.send(:table_exists?, @model)
    assert FullSearch::Index.send(:table_exists?, model_two)
  ensure
    FullSearch.deregister_model(model_two)
    begin
      FullSearch::Index.drop!(model_two)
    rescue
      nil
    end
  end

  def test_setup_for_tests_disables_lock_rebuilds_and_enables_inline_jobs
    original_lock_rebuilds = FullSearch.config.lock_rebuilds
    original_auto_rebuild = FullSearch.config.auto_rebuild_on_stale_query
    original_stale_behavior = FullSearch.config.stale_query_behavior
    original_adapter = ActiveJob::Base.queue_adapter

    FullSearch::TestHelpers.setup_for_tests!

    refute FullSearch.config.lock_rebuilds
    assert FullSearch.config.auto_rebuild_on_stale_query
    assert_equal :raise, FullSearch.config.stale_query_behavior
    assert_instance_of ActiveJob::QueueAdapters::InlineAdapter, ActiveJob::Base.queue_adapter
  ensure
    FullSearch.config.lock_rebuilds = original_lock_rebuilds
    FullSearch.config.auto_rebuild_on_stale_query = original_auto_rebuild
    FullSearch.config.stale_query_behavior = original_stale_behavior
    ActiveJob::Base.queue_adapter = original_adapter
  end

  def test_with_full_search_async_jobs_inline_restores_adapter
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    with_full_search_async_jobs_inline do
      assert_instance_of ActiveJob::QueueAdapters::InlineAdapter, ActiveJob::Base.queue_adapter
    end

    assert_instance_of ActiveJob::QueueAdapters::TestAdapter, ActiveJob::Base.queue_adapter
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  def test_with_full_search_models_registered_deregisters_after_block
    initial_models = FullSearch.models.dup

    with_full_search_models_registered do
      extra = Class.new(Customer) do
        full_search { field :first_name, weight: 5 }
      end
      extra.table_name = "customers"
      assert_includes FullSearch.models, extra
    end

    assert_equal initial_models, FullSearch.models
  end
end
