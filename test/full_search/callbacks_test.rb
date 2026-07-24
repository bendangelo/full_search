# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

ActiveJob::Base.queue_adapter = :inline

class FullSearch::CallbacksTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def test_source_field_reindex_is_async_by_default
    ActiveJob::Base.queue_adapter = :test
    model = Class.new(Customer) do
      def self.name
        "AsyncSourceCustomer"
      end
      full_search do
        field :computed, source: -> { "customer_#{first_name}" }
        filter :account_id, required: true
      end
    end
    Object.const_set(:AsyncSourceCustomer, model)
    model.table_name = "customers"
    FullSearch::Index.rebuild!(model)

    account = Account.create!(name: "Acme")
    assert_enqueued_jobs 1 do
      model.create!(account_id: account.id, first_name: "Sam")
    end
  ensure
    begin
      FullSearch::Index.drop!(model)
    rescue
      nil
    end
    Object.send(:remove_const, :AsyncSourceCustomer) if Object.const_defined?(:AsyncSourceCustomer)
  end

  def test_reindex_field_silently_returns_when_fts_table_missing
    model = Class.new(Customer) do
      def self.name
        "MissingTableReindexCustomer"
      end
      full_search do
        field :computed, source: -> { "customer_#{first_name}" }
        filter :account_id, required: true
      end
    end
    Object.const_set(:MissingTableReindexCustomer, model)
    model.table_name = "customers"
    FullSearch::Index.rebuild!(model)

    account = Account.create!(name: "Acme")
    customer = model.create!(account_id: account.id, first_name: "Sam")

    fts_table = FullSearch::Index.fts_table_name(model)
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS #{ActiveRecord::Base.connection.quote_table_name(fts_table)}")

    assert_nothing_raised do
      FullSearch::Callbacks.reindex_field!(customer, "computed")
    end
  ensure
    begin
      FullSearch::Index.drop!(model)
    rescue
      nil
    end
    Object.send(:remove_const, :MissingTableReindexCustomer) if Object.const_defined?(:MissingTableReindexCustomer)
  end

  def test_remove_record_silently_returns_when_fts_table_missing
    model = Class.new(Customer) do
      def self.name
        "MissingTableRemoveCustomer"
      end
      full_search do
        field :computed, source: -> { "customer_#{first_name}" }
        filter :account_id, required: true
      end
    end
    Object.const_set(:MissingTableRemoveCustomer, model)
    model.table_name = "customers"
    FullSearch::Index.rebuild!(model)

    account = Account.create!(name: "Acme")
    customer = model.create!(account_id: account.id, first_name: "Sam")

    fts_table = FullSearch::Index.fts_table_name(model)
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS #{ActiveRecord::Base.connection.quote_table_name(fts_table)}")

    assert_nothing_raised do
      FullSearch::Callbacks.remove_record!(customer)
    end
  ensure
    begin
      FullSearch::Index.drop!(model)
    rescue
      nil
    end
    Object.send(:remove_const, :MissingTableRemoveCustomer) if Object.const_defined?(:MissingTableRemoveCustomer)
  end

  def test_dependent_reindex_with_sync_mode
    tbl = "dep_sync_custs"
    ActiveRecord::Schema.define do
      create_table tbl, force: true do |t|
        t.references :account, null: false
        t.string :first_name
      end
    end

    model = Class.new(ActiveRecord::Base) do
      self.table_name = tbl
      def self.name
        "DependentSyncCust"
      end
      belongs_to :account
    end
    model.instance_variable_set(:@__full_search_callbacks_installed, true)
    model.full_search do
      field :computed, source: -> { "val_#{first_name}" }, reindex_on: :account, async: false
      filter :account_id, required: true
    end
    Object.const_set(:DependentSyncCust, model)
    FullSearch::Index.rebuild!(model)

    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "A")
    model.create!(account_id: account.id, first_name: "B")

    field = model.full_search_dsl.fields.find { |f| f.name == "computed" }
    FullSearch::Callbacks.reindex_dependents!(account.reload, model, field)

    rows = ActiveRecord::Base.connection.execute(
      "SELECT rowid, computed FROM #{FullSearch::Index.fts_table_name(model)} ORDER BY rowid"
    )
    assert_equal 2, rows.count
    assert_equal "val_A", rows[0]["computed"]
    assert_equal "val_B", rows[1]["computed"]
  ensure
    begin
      ActiveRecord::Base.connection.drop_table(tbl)
    rescue
      nil
    end
    begin
      FullSearch::Index.drop!(model)
    rescue
      nil
    end
    Object.send(:remove_const, :DependentSyncCust) if Object.const_defined?(:DependentSyncCust)
  end

  def test_dependent_reindex_with_async_mode
    tbl = "dep_async_custs"
    ActiveRecord::Schema.define do
      create_table tbl, force: true do |t|
        t.references :account, null: false
        t.string :first_name
      end
    end

    model = Class.new(ActiveRecord::Base) do
      self.table_name = tbl
      def self.name
        "DependentAsyncCust"
      end
      belongs_to :account
    end
    model.instance_variable_set(:@__full_search_callbacks_installed, true)
    model.full_search do
      field :computed, source: -> { "val_#{first_name}" }, reindex_on: :account
      filter :account_id, required: true
    end
    Object.const_set(:DependentAsyncCust, model)
    FullSearch::Index.rebuild!(model)

    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "A")

    ActiveJob::Base.queue_adapter = :test
    field = model.full_search_dsl.fields.find { |f| f.name == "computed" }
    assert_enqueued_jobs 1 do
      FullSearch::Callbacks.reindex_dependents!(account.reload, model, field)
    end
  ensure
    begin
      ActiveRecord::Base.connection.drop_table(tbl)
    rescue
      nil
    end
    begin
      FullSearch::Index.drop!(model)
    rescue
      nil
    end
    Object.send(:remove_const, :DependentAsyncCust) if Object.const_defined?(:DependentAsyncCust)
  end

  def test_source_field_reindex_is_sync_when_async_source_false
    ActiveJob::Base.queue_adapter = :inline
    model = Class.new(Customer) do
      def self.name
        "SyncSourceCustomer"
      end
      full_search do
        field :computed, source: -> { "customer_#{first_name}" }, async_source: false
        filter :account_id, required: true
      end
    end
    Object.const_set(:SyncSourceCustomer, model)
    model.table_name = "customers"
    FullSearch::Index.rebuild!(model)

    account = Account.create!(name: "Acme")
    customer = model.create!(account_id: account.id, first_name: "Sam")

    row = ActiveRecord::Base.connection.execute(
      "SELECT computed FROM #{FullSearch::Index.fts_table_name(model)} WHERE rowid = #{customer.id}"
    ).first
    assert_equal "customer_Sam", row["computed"]
  ensure
    begin
      FullSearch::Index.drop!(model)
    rescue
      nil
    end
    Object.send(:remove_const, :SyncSourceCustomer) if Object.const_defined?(:SyncSourceCustomer)
  end
end
