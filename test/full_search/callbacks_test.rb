# frozen_string_literal: true

require "test_helper"

ActiveJob::Base.queue_adapter = :inline

class FullSearch::CallbacksTest < ActiveSupport::TestCase
  def setup
    @vehicle_model = Class.new(Vehicle) do
      full_search do
        field :customer_name, weight: 3, source: -> { customer&.full_name }, reindex_on: :customer, async: false
        filter :account_id, required: true
      end
    end
    @vehicle_model.table_name = "vehicles"
    FullSearch::Index.rebuild!(@vehicle_model)
  end

  def teardown
    Customer.delete_all
    Vehicle.delete_all
    FullSearch::Index.drop!(@vehicle_model) rescue nil
  end

  def test_callbacks_are_idempotent
    model = Class.new(Vehicle) do
      full_search do
        field :computed, source: -> { make&.upcase }
        filter :account_id, required: true
      end
    end
    model.table_name = "vehicles"
    FullSearch::Index.rebuild!(model)

    save_callbacks = model._save_callbacks.to_a.dup
    destroy_callbacks = model._destroy_callbacks.to_a.dup

    model.full_search do
      field :computed, source: -> { make&.upcase }
      filter :account_id, required: true
    end

    assert_equal save_callbacks.size, model._save_callbacks.to_a.size
    assert_equal destroy_callbacks.size, model._destroy_callbacks.to_a.size
  ensure
    FullSearch::Callbacks.uninstall!(model)
    FullSearch::Index.drop!(model) rescue nil
  end

  def test_source_field_syncs_on_save
    account = Account.create!(name: "Acme")
    customer = Customer.create!(account_id: account.id, first_name: "Sam")
    vehicle = @vehicle_model.create!(account_id: account.id, customer_id: customer.id)

    assert_equal "Sam", indexed_value(vehicle, "customer_name")

    customer.update!(first_name: "Samantha")
    vehicle.reload
    assert_equal "Samantha", indexed_value(vehicle, "customer_name")
  end

  private

  def indexed_value(vehicle, field)
    table = FullSearch::Index.fts_table_name(@vehicle_model)
    ActiveRecord::Base.connection.execute(
      "SELECT #{field} FROM #{table} WHERE rowid = #{vehicle.id}"
    ).first[field]
  end
end
