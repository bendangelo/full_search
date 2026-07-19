# frozen_string_literal: true

require "test_helper"

class FullSearch::IndexTest < ActiveSupport::TestCase
  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"
    begin
      FullSearch::Index.drop!(@model)
    rescue
      nil
    end
  end

  def teardown
    Customer.delete_all
  end

  def test_ensure_table_creates_virtual_table
    FullSearch::Index.ensure_table!(@model)
    assert FullSearch::Index.send(:table_exists?, @model)
  end

  def test_rebuild_populates_source_fields
    account = Account.create!(name: "Acme")

    vehicle = Vehicle.create!(account_id: account.id, make: "Honda")

    search_model = Class.new(Vehicle) do
      full_search do
        field :make_search, weight: 5, source: -> { make&.upcase }
        filter :account_id, required: true
      end
    end
    search_model.table_name = "vehicles"

    FullSearch::Index.rebuild!(search_model)

    row = ActiveRecord::Base.connection.execute(
      "SELECT make_search FROM #{FullSearch::Index.fts_table_name(search_model)} WHERE rowid = #{vehicle.id}"
    ).first

    assert_equal "HONDA", row["make_search"]
  end

  def test_rebuild_populates_rows
    account = Account.create!(name: "Acme")
    @model.create!(account_id: account.id, first_name: "Sam", last_name: "Smith")
    FullSearch::Index.rebuild!(@model)

    rows = ActiveRecord::Base.connection.execute(
      "SELECT * FROM #{FullSearch::Index.fts_table_name(@model)}"
    )
    assert_equal 1, rows.count
  end

  def test_drop_removes_fts_table
    FullSearch::Index.ensure_table!(@model)
    assert FullSearch::Index.send(:table_exists?, @model)

    FullSearch::Index.drop!(@model)
    refute FullSearch::Index.send(:table_exists?, @model)
  end

  def test_ensure_table_is_idempotent
    FullSearch::Index.ensure_table!(@model)
    assert FullSearch::Index.send(:table_exists?, @model)

    FullSearch::Index.ensure_table!(@model)
    assert FullSearch::Index.send(:table_exists?, @model)
  end

  def test_rebuild_lock_does_not_store_empty_config
    FullSearch::Index.rebuild!(@model)
    stored = ActiveRecord::Base.connection.execute(
      "SELECT config_hash FROM full_search_index_versions WHERE table_name = 'customers'"
    ).first
    refute_equal "", stored["config_hash"]
    refute_equal "__rebuilding__", stored["config_hash"]
  end

  def test_rebuild_if_needed_returns_false_when_current
    FullSearch::Index.rebuild!(@model)
    refute FullSearch::Index.rebuild_if_needed!(@model)
  end
end
