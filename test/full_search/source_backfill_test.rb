# frozen_string_literal: true

require "test_helper"

class FullSearch::SourceBackfillTest < ActiveSupport::TestCase
  def setup
    clean_fts_tables!
    @account = Account.create!(name: "Acme")
  end

  def teardown
    full_search_cleanup(@model)
    Customer.delete_all
    Account.delete_all
    clean_fts_tables!
  end

  def test_sourced_fields_are_backfilled_during_rebuild
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :computed, weight: 1, source: -> { "source_value_#{first_name}" }
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"

    @model.create!(account_id: @account.id, first_name: "Sarah")
    FullSearch::Index.rebuild!(@model)

    row = ActiveRecord::Base.connection.execute(
      "SELECT computed FROM #{FullSearch::Index.fts_table_name(@model)}"
    ).first

    assert_equal "source_value_Sarah", row["computed"]
  end

  def test_multiple_sourced_fields_are_all_backfilled
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :greeting, weight: 1, source: -> { "Hello #{first_name}" }
        field :farewell, weight: 1, source: -> { "Goodbye #{first_name}" }
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"

    @model.create!(account_id: @account.id, first_name: "Alex")
    FullSearch::Index.rebuild!(@model)

    rows = ActiveRecord::Base.connection.execute(
      "SELECT greeting, farewell FROM #{FullSearch::Index.fts_table_name(@model)}"
    )
    row = rows.first

    assert_equal "Hello Alex", row["greeting"]
    assert_equal "Goodbye Alex", row["farewell"]
  end

  def test_sourced_fields_remain_after_trigger_update
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :computed, weight: 1, source: -> { "val_#{first_name}" }
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"

    record = @model.create!(account_id: @account.id, first_name: "Ben")
    FullSearch::Index.rebuild!(@model)

    row = ActiveRecord::Base.connection.execute(
      "SELECT computed FROM #{FullSearch::Index.fts_table_name(@model)} WHERE rowid = #{record.id}"
    ).first
    assert_equal "val_Ben", row["computed"]

    record.update!(first_name: "BenUpdated")

    row = ActiveRecord::Base.connection.execute(
      "SELECT computed FROM #{FullSearch::Index.fts_table_name(@model)} WHERE rowid = #{record.id}"
    ).first
    assert_equal "val_BenUpdated", row["computed"]
  end

  private

  def clean_fts_tables!
    ActiveRecord::Base.connection.execute(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE '%_fts%'"
    ).each { |r| ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS #{r['name']}") }
    ActiveRecord::Base.connection.execute(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_fts%'"
    ).each { |r| ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS #{r['name']}") }
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS full_search_index_versions")
  end

  def full_search_cleanup(model)
    return unless model
    FullSearch::Index.drop!(model) rescue nil
  end
end
