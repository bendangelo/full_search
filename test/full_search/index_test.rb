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

  def test_rebuild_populates_multiple_source_fields
    account = Account.create!(name: "Acme")
    vehicle = Vehicle.create!(account_id: account.id, make: "Honda", model: "Civic")

    search_model = Class.new(Vehicle) do
      full_search do
        field :make_search, weight: 5, source: -> { make&.upcase }
        field :model_search, weight: 3, source: -> { model&.downcase }
        filter :account_id, required: true
      end
    end
    search_model.table_name = "vehicles"

    begin
      FullSearch::Index.rebuild!(search_model)

      fts_table = FullSearch::Index.fts_table_name(search_model)
      row = ActiveRecord::Base.connection.execute(
        "SELECT make_search, model_search FROM #{fts_table} WHERE rowid = #{vehicle.id}"
      ).first

      assert_equal "HONDA", row["make_search"]
      assert_equal "civic", row["model_search"]
    ensure
      FullSearch::Index.drop!(search_model)
      Customer.delete_all
      Account.delete_all
    end
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

  def test_missing_table_returns_true_when_table_does_not_exist
    FullSearch::Index.drop!(@model)
    assert FullSearch::Index.missing_table?(@model)
  end

  def test_missing_table_returns_false_when_table_exists
    FullSearch::Index.ensure_table!(@model)
    refute FullSearch::Index.missing_table?(@model)
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

  def test_conditional_index_excludes_unmatched_rows
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
        index_if sql: "first_name = 'Keep'"
      end
    end
    model.table_name = "customers"

    account = Account.create!(name: "Acme")
    keep = model.create!(account_id: account.id, first_name: "Keep")
    drop = model.create!(account_id: account.id, first_name: "Drop")

    begin
      FullSearch::Index.rebuild!(model)

      results = model.full_search("Keep", filters: {account_id: account.id})
      assert_includes results.map(&:id), keep.id
      refute_includes results.map(&:id), drop.id if drop

      fts_count = ActiveRecord::Base.connection.execute(
        "SELECT COUNT(*) AS c FROM #{FullSearch::Index.fts_table_name(model)}"
      ).first["c"]
      assert_equal 1, fts_count
    ensure
      FullSearch::Index.drop!(model)
    end
  end

  def test_conditional_index_update_removes_row_when_condition_fails
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
        index_if sql: "first_name = 'Keep'"
      end
    end
    model.table_name = "customers"

    account = Account.create!(name: "Acme")
    keep = model.create!(account_id: account.id, first_name: "Keep")

    begin
      FullSearch::Index.rebuild!(model)

      keep.update!(first_name: "Drop")

      results = model.full_search("Keep", filters: {account_id: account.id})
      refute_includes results.map(&:id), keep.id

      fts_count = ActiveRecord::Base.connection.execute(
        "SELECT COUNT(*) AS c FROM #{FullSearch::Index.fts_table_name(model)}"
      ).first["c"]
      assert_equal 0, fts_count
    ensure
      FullSearch::Index.drop!(model)
    end
  end

  def test_conditional_index_inserts_on_update_when_condition_now_true
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
        index_if sql: "first_name = 'Keep'"
      end
    end
    model.table_name = "customers"

    account = Account.create!(name: "Acme")
    record = model.create!(account_id: account.id, first_name: "Drop")

    begin
      FullSearch::Index.rebuild!(model)

      record.update!(first_name: "Keep")

      results = model.full_search("Keep", filters: {account_id: account.id})
      assert_includes results.map(&:id), record.id

      fts_count = ActiveRecord::Base.connection.execute(
        "SELECT COUNT(*) AS c FROM #{FullSearch::Index.fts_table_name(model)}"
      ).first["c"]
      assert_equal 1, fts_count
    ensure
      FullSearch::Index.drop!(model)
    end
  end

  def test_fts_column_uses_as_alias
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :computed, weight: 1, source: -> { "hello_#{first_name}" }, as: :greeting, async_source: false
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")

    begin
      FullSearch::Index.rebuild!(model)
      fts_table = FullSearch::Index.fts_table_name(model)

      columns = ActiveRecord::Base.connection.execute("PRAGMA table_info(#{fts_table})").map { |r| r["name"] }
      assert_includes columns, "greeting", "FTS DDL should create column with alias name"
      refute_includes columns, "computed", "FTS DDL should not create column with field name"

      record = model.create!(account_id: account.id, first_name: "Sam")
      row1 = ActiveRecord::Base.connection.execute(
        "SELECT greeting FROM #{fts_table} WHERE rowid = #{record.id}"
      ).first
      assert_equal "hello_Sam", row1["greeting"], "Backfill/trigger should write source value to alias column"

      record.update!(first_name: "SamUpdated")
      row2 = ActiveRecord::Base.connection.execute(
        "SELECT greeting FROM #{fts_table} WHERE rowid = #{record.id}"
      ).first
      assert_equal "hello_SamUpdated", row2["greeting"], "Reindex callback should update alias column"
    ensure
      FullSearch::Index.drop!(model)
      Customer.delete_all
      Account.delete_all
    end
  end

  def test_rebuild_if_needed_detects_stale_config_hash
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"

    begin
      FullSearch::Index.rebuild!(model)
      refute FullSearch::Index.rebuild_if_needed!(model), "should be false when config matches"

      ActiveRecord::Base.connection.execute(
        "UPDATE full_search_index_versions SET config_hash = 'tampered' WHERE table_name = 'customers'"
      )

      assert FullSearch::Index.rebuild_if_needed!(model), "should detect stale config and trigger rebuild"
    ensure
      FullSearch::Index.drop!(model)
      Customer.delete_all
      Account.delete_all
    end
  end

  def test_trigram_column_uses_as_alias
    model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5, as: :fname
        field :last_name, weight: 5
        filter :account_id, required: true
        tokenize "trigram"
        typo_tolerance
      end
    end
    model.table_name = "customers"
    account = Account.create!(name: "Acme")

    begin
      record = model.create!(account_id: account.id, first_name: "Sam", last_name: "Smith")
      FullSearch::Index.rebuild!(model)

      trigram_table = FullSearch::Index.trigram_table_name(model)
      columns = ActiveRecord::Base.connection.execute("PRAGMA table_info(#{trigram_table})").map { |r| r["name"] }
      assert_includes columns, "fname", "Trigram DDL should use alias column name"
      refute_includes columns, "first_name", "Trigram DDL should not use field name"

      row = ActiveRecord::Base.connection.execute(
        "SELECT fname, last_name FROM #{trigram_table} WHERE rowid = #{record.id}"
      ).first
      assert_equal "Sam", row["fname"], "Trigram backfill should write value to alias column"
      assert_equal "Smith", row["last_name"]
    ensure
      FullSearch::Index.drop!(model)
      Customer.delete_all
      Account.delete_all
    end
  end
end
