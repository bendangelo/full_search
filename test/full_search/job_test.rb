# frozen_string_literal: true

require "test_helper"

class FullSearch::JobTest < ActiveSupport::TestCase
  def test_optimize_job_runs_without_error
    old_models = FullSearch.models.dup
    FullSearch.models.clear
    assert_nothing_raised do
      FullSearch::OptimizeJob.perform_now
    end
  ensure
    FullSearch.models.replace(old_models)
  end

  def test_reindex_job_updates_source_field
    ActiveJob::Base.queue_adapter = :inline
    account = Account.create!(name: "Acme")
    customer = Customer.create!(account_id: account.id, first_name: "Sam")
    vehicle = Vehicle.create!(account_id: account.id, customer_id: customer.id, make: "Honda")

    model = Class.new(Vehicle) do
      def self.name
        "VehicleForReindexTest"
      end

      full_search do
        field :customer_name, weight: 3, source: -> { customer&.full_name }
        filter :account_id, required: true
      end
    end
    Object.const_set(:VehicleForReindexTest, model)
    model.table_name = "vehicles"
    FullSearch::Index.rebuild!(model)

    customer.update!(first_name: "Samantha")
    FullSearch::ReindexJob.perform_now(model.name, vehicle.id, "customer_name")

    fts_table = FullSearch::Index.fts_table_name(model)
    row = ActiveRecord::Base.connection.execute(
      "SELECT customer_name FROM #{ActiveRecord::Base.connection.quote_table_name(fts_table)} WHERE rowid = #{ActiveRecord::Base.connection.quote(vehicle.id)}"
    ).first
    assert_equal "Samantha", row["customer_name"]
  ensure
    Customer.delete_all
    Vehicle.delete_all
    Account.delete_all
    Object.send(:remove_const, :VehicleForReindexTest) if Object.const_defined?(:VehicleForReindexTest)
  end

  def test_reindex_job_uses_low_queue
    assert_equal "low", FullSearch::ReindexJob.queue_name
  end

  def test_reindex_job_without_field_name_reindexes_all_source_fields
    ActiveJob::Base.queue_adapter = :inline
    account = Account.create!(name: "Acme")
    customer = Customer.create!(account_id: account.id, first_name: "Sam")
    vehicle = Vehicle.create!(account_id: account.id, customer_id: customer.id, make: "Honda")

    model = Class.new(Vehicle) do
      def self.name
        "VehicleForFullReindexTest"
      end
      full_search do
        field :customer_name, source: -> { customer&.full_name }
        field :make_search, source: -> { make&.upcase }
        filter :account_id, required: true
      end
    end
    Object.const_set(:VehicleForFullReindexTest, model)
    model.table_name = "vehicles"
    FullSearch::Index.rebuild!(model)

    FullSearch::ReindexJob.perform_now(model.name, vehicle.id)

    fts_table = FullSearch::Index.fts_table_name(model)
    row = ActiveRecord::Base.connection.execute(
      "SELECT customer_name, make_search FROM #{ActiveRecord::Base.connection.quote_table_name(fts_table)} WHERE rowid = #{vehicle.id}"
    ).first
    assert_equal "Sam", row["customer_name"]
    assert_equal "HONDA", row["make_search"]
  ensure
    begin
      Object.send(:remove_const, :VehicleForFullReindexTest) if Object.const_defined?(:VehicleForFullReindexTest)
    rescue
      nil
    end
  end

  def test_backfill_job_uses_low_queue
    assert_equal "low", FullSearch::BackfillJob.queue_name
  end

  def test_backfill_job_rebuilds_index
    ActiveJob::Base.queue_adapter = :inline
    account = Account.create!(name: "Acme")
    customer = Customer.create!(account_id: account.id, first_name: "Sam")

    model = Class.new(Customer) do
      def self.name
        "CustomerForBackfillTest"
      end
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    Object.const_set(:CustomerForBackfillTest, model)
    model.table_name = "customers"
    FullSearch::Index.rebuild!(model)

    FullSearch::BackfillJob.perform_now(model.name)

    results = model.full_search("Sam", filters: {account_id: account.id})
    assert_equal [customer.id], results.to_a.map(&:id)
  ensure
    begin
      Object.send(:remove_const, :CustomerForBackfillTest) if Object.const_defined?(:CustomerForBackfillTest)
    rescue
      nil
    end
  end
end
