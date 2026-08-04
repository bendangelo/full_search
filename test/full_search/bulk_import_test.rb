# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

class FullSearch::BulkImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    ActiveJob::Base.queue_adapter = :test
    @model = Class.new(Customer) do
      def self.name
        "BulkImportCustomer"
      end
      full_search do
        field :first_name
        field :computed, source: -> { "c_#{first_name}" }
        filter :account_id, required: true
      end
    end
    Object.const_set(:BulkImportCustomer, @model)
    @model.table_name = "customers"
    FullSearch::Index.rebuild!(@model)
    @account = Account.create!(name: "Acme")
  end

  def teardown
    Customer.delete_all
    Account.delete_all
    begin
      FullSearch::Index.drop!(@model)
    rescue
      nil
    end
    Object.send(:remove_const, :BulkImportCustomer) if Object.const_defined?(:BulkImportCustomer)
  end

  def test_bulk_import_disables_triggers_and_callbacks
    FullSearch.bulk_import(@model) do
      customer = @model.create!(account_id: @account.id, first_name: "Sam")

      trigger_names = ActiveRecord::Base.connection.execute(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='customers'"
      ).map { |r| r["name"] }
      assert_empty trigger_names & ["#{FullSearch::Index.fts_table_name(@model)}_ai"]

      fts_count = ActiveRecord::Base.connection.execute(
        "SELECT COUNT(*) AS c FROM #{FullSearch::Index.fts_table_name(@model)} WHERE rowid = #{customer.id}"
      ).first["c"]
      assert_equal 0, fts_count

      assert_no_enqueued_jobs
    end

    assert_enqueued_jobs 1, only: FullSearch::BackfillJob
  end

  def test_backfill_job_restores_index
    FullSearch.bulk_import(@model) do
      @model.insert_all!([
        {account_id: @account.id, first_name: "Sam", created_at: Time.current, updated_at: Time.current}
      ])
    end

    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("Sam", filters: {account_id: @account.id})
    assert_equal 1, results.to_a.length
  end

  def test_end_bulk_import_raises_when_trigger_restore_fails
    # Simulate create_triggers! failing so the ensure path can't restore triggers.
    original = FullSearch::Index.method(:create_triggers!)
    FullSearch::Index.define_singleton_method(:create_triggers!) { |*_args| raise StandardError, "DDL explosion" }

    assert_raises(FullSearch::TriggerRestoreError) do
      FullSearch.bulk_import(@model) {}  # triggers dropped in start, restore fails in end
    end

    # Triggers are still dropped — the caller now knows instead of silent rot.
    assert FullSearch::Index.missing_triggers?(@model), "triggers should remain dropped after failed restore"
  ensure
    FullSearch::Index.define_singleton_method(:create_triggers!, original) if original
    FullSearch::Index.rebuild!(@model)
  end

  def test_ensure_table_skips_triggers_during_bulk_import
    FullSearch::Index.drop!(@model)
    FullSearch::Index.verified_tables.delete(@model.table_name)

    FullSearch.bulk_import(@model) do
      FullSearch::Index.ensure_table!(@model)

      trigger_names = ActiveRecord::Base.connection.execute(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='customers'"
      ).map { |r| r["name"] }
      assert_empty trigger_names
    end

    assert_enqueued_jobs 1, only: FullSearch::BackfillJob
  end
end
