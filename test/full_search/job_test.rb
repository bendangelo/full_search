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
  end
end
