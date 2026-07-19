# frozen_string_literal: true

require "test_helper"

class FullSearch::EncryptedSourceFieldTest < ActiveSupport::TestCase
  def setup
    clean_fts_tables!
    @account = Account.create!(name: "Acme")

    @model = Class.new(Vehicle) do
      full_search({tokenize: :trigram}) do
        field :license_plate, weight: 5, source: -> { license_plate&.to_s&.strip&.upcase }
        field :vin_last8, weight: 2, source: -> { vin&.last(8)&.upcase }, as: :vin
        field :make, weight: 4
        field :model, weight: 4
        exact_match :vin, source: -> { vin }
        exact_match :license_plate, source: -> { license_plate&.to_s&.strip&.upcase }
        filter :account_id, required: true
        rank_by :updated_at, :desc
        highlight
        typo_tolerance
      end
    end
    @model.table_name = "vehicles"

    # Add updated_at column if missing
    extend_vehicles_schema
  end

  def teardown
    begin
      FullSearch::Index.drop!(@model)
    rescue
      nil
    end
    Vehicle.delete_all
    Account.delete_all
    clean_fts_tables!
  end

  # --- FTS table value correctness ---

  def test_fts_table_contains_source_value_after_rebuild
    @model.create!(account_id: @account.id, make: "Honda", license_plate: " ABC-1234 ")
    FullSearch::Index.rebuild!(@model)

    row = ActiveRecord::Base.connection.execute(
      "SELECT license_plate FROM #{FullSearch::Index.fts_table_name(@model)}"
    ).first

    assert_equal "ABC-1234", row["license_plate"]
  end

  def test_fts_table_source_value_without_lock_rebuilds
    original = FullSearch.config.lock_rebuilds
    FullSearch.config.lock_rebuilds = false

    @model.create!(account_id: @account.id, make: "Honda", license_plate: "ABC-1234")
    FullSearch::Index.rebuild!(@model)

    row = ActiveRecord::Base.connection.execute(
      "SELECT license_plate FROM #{FullSearch::Index.fts_table_name(@model)}"
    ).first

    assert_equal "ABC-1234", row["license_plate"]
  ensure
    FullSearch.config.lock_rebuilds = original
  end

  # --- Search results ---

  def test_search_finds_vehicle_by_license_plate
    vehicle = @model.create!(account_id: @account.id, make: "Honda", license_plate: "ABC-1234")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("ABC-1234", filters: {account_id: @account.id}).to_a

    assert_includes results.map(&:id), vehicle.id
  end

  def test_search_finds_vehicle_by_lowercase_license_plate
    vehicle = @model.create!(account_id: @account.id, make: "Honda", license_plate: "ABC-1234")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("abc-1234", filters: {account_id: @account.id}).to_a

    assert_includes results.map(&:id), vehicle.id
  end

  def test_search_finds_vehicle_by_license_plate_prefix
    vehicle = @model.create!(account_id: @account.id, make: "Honda", license_plate: "ABC-1234")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("ABC", filters: {account_id: @account.id}).to_a

    assert_includes results.map(&:id), vehicle.id
  end

  def test_search_finds_vehicle_by_exact_match_on_license_plate
    vehicle = @model.create!(account_id: @account.id, make: "Honda", license_plate: "ABC-1234")
    FullSearch::Index.rebuild!(@model)

    ids = FullSearch::ExactMatch.ids_for(@model, "ABC-1234", {account_id: @account.id})

    assert_includes ids, vehicle.id
  end

  def test_search_finds_vehicle_by_lowercase_exact_match
    vehicle = @model.create!(account_id: @account.id, make: "Honda", license_plate: "ABC-1234")
    FullSearch::Index.rebuild!(@model)

    ids = FullSearch::ExactMatch.ids_for(@model, "abc-1234", {account_id: @account.id})

    assert_includes ids, vehicle.id
  end

  # --- Highlight fields ---

  def test_highlight_fields_includes_license_plate
    @model.create!(account_id: @account.id, make: "Honda", license_plate: "ABC-1234")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("ABC-1234", filters: {account_id: @account.id}, highlight_fields: true).to_a
    refute results.empty?
    result = results.first

    assert result.respond_to?(:full_search_highlight_fields)
    assert_includes result.full_search_highlight_fields["license_plate"], "<mark>"
  end

  def test_highlight_fields_omits_unmatched_fields
    @model.create!(account_id: @account.id, make: "Honda", model: "Civic", license_plate: "ABC-1234")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("ABC-1234", filters: {account_id: @account.id}, highlight_fields: true).to_a
    result = results.first

    assert_nil result.full_search_highlight_fields["make"]
    assert_nil result.full_search_highlight_fields["model"]
  end

  def test_highlight_fields_on_short_prefix
    @model.create!(account_id: @account.id, make: "Honda", license_plate: "ABC-1234")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("ABC", filters: {account_id: @account.id}, highlight_fields: true).to_a
    refute results.empty?
    result = results.first

    assert_includes result.full_search_highlight_fields["license_plate"], "<mark>"
  end

  def test_highlight_snippet_includes_license_plate
    @model.create!(account_id: @account.id, make: "Honda", license_plate: "ABC-1234")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("ABC-1234", filters: {account_id: @account.id}, highlight: true).to_a
    refute results.empty?
    result = results.first

    assert result.respond_to?(:full_search_snippet)
    assert result.full_search_snippet.include?("<mark>")
  end

  private

  def clean_fts_tables!
    ActiveRecord::Base.connection.execute(
      "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE '%_fts%'"
    ).each { |r| ActiveRecord::Base.connection.execute("DROP TRIGGER IF EXISTS #{r["name"]}") }
    ActiveRecord::Base.connection.execute(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_fts%'"
    ).each { |r| ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS #{r["name"]}") }
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS full_search_index_versions")
  end

  def extend_vehicles_schema
    conn = ActiveRecord::Base.connection
    unless conn.column_exists?(:vehicles, :updated_at)
      conn.add_column(:vehicles, :updated_at, :datetime)
      Vehicle.reset_column_information
    end
  end
end
