# frozen_string_literal: true

require "test_helper"

class FullSearch::SoftDeleteTest < ActiveSupport::TestCase
  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
        soft_delete_column :discarded_at
      end
    end
    @model.table_name = "customers"
    FullSearch::Index.rebuild!(@model)
  end

  def teardown
    Customer.delete_all
  end

  def test_soft_deleted_record_excluded_from_search
    account = Account.create!(name: "Acme")
    customer = @model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("Sam", filters: { account_id: account.id })
    assert_includes results.to_a, customer

    customer.update!(discarded_at: Time.current)
    results = @model.full_search("Sam", filters: { account_id: account.id })
    refute_includes results.to_a, customer
  end

  def test_soft_deleted_record_included_when_flag_set
    account = Account.create!(name: "Acme")
    customer = @model.create!(account_id: account.id, first_name: "Sam", discarded_at: Time.current)
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("Sam", filters: { account_id: account.id }, include_soft_deleted: true)
    assert_includes results.to_a, customer
  end

  def test_soft_delete_removes_from_fts_index
    account = Account.create!(name: "Acme")
    customer = @model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(@model)

    customer.update!(discarded_at: Time.current)

    fts_count = ActiveRecord::Base.connection.execute(
      "SELECT COUNT(*) AS c FROM #{FullSearch::Index.fts_table_name(@model)} WHERE rowid = #{customer.id}"
    ).first["c"]
    assert_equal 0, fts_count
  end

  def test_restore_re_adds_to_fts_index
    account = Account.create!(name: "Acme")
    customer = @model.create!(account_id: account.id, first_name: "Sam", discarded_at: Time.current)
    FullSearch::Index.rebuild!(@model)

    customer.update!(discarded_at: nil)

    results = @model.full_search("Sam", filters: { account_id: account.id })
    assert_includes results.to_a, customer
  end

  def test_soft_deleted_records_not_leaked_by_typo_fallback
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
        typo_tolerance
        soft_delete_column :discarded_at
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")
    good = model.create!(account_id: account.id, first_name: "Samantha", last_name: "Smith")
    model.create!(account_id: account.id, first_name: "Samantha", last_name: "Smith", discarded_at: Time.current)
    FullSearch::Index.rebuild!(model)

    results = model.full_search("saman", filters: { account_id: account.id })
    assert_equal 1, results.size
    assert_equal good.id, results.first.id
  end

  def test_non_soft_deleted_model_still_works
    account = Account.create!(name: "Acme")
    vehicle_model = Class.new(Vehicle) do
      full_search do
        field :make, weight: 5
        filter :account_id, required: true
      end
    end
    vehicle_model.table_name = "vehicles"
    FullSearch::Index.rebuild!(vehicle_model)

    vehicle = vehicle_model.create!(account_id: account.id, make: "Honda")
    results = vehicle_model.full_search("Honda", filters: { account_id: account.id })
    assert_includes results.to_a, vehicle

    vehicle.update!(make: "Toyota")
    results = vehicle_model.full_search("Toyota", filters: { account_id: account.id })
    assert_includes results.to_a, vehicle

    vehicle.destroy!
    results = vehicle_model.full_search("Toyota", filters: { account_id: account.id })
    refute_includes results.to_a, vehicle
  end
end
