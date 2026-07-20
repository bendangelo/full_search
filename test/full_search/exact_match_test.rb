# frozen_string_literal: true

require "test_helper"

class FullSearch::ExactMatchTest < ActiveSupport::TestCase
  def setup
    @account = Account.create!(name: "Acme")
  end

  def teardown
    Vehicle.delete_all
    Account.delete_all
  end

  def test_exact_match_evaluates_source_proc
    search_model = Class.new(Vehicle) do
      full_search do
        exact_match :make, source: -> { make&.upcase }
        filter :account_id, required: true
      end
    end
    search_model.table_name = "vehicles"

    FullSearch::Index.rebuild!(search_model)

    vehicle = Vehicle.create!(account_id: @account.id, make: "HONDA")

    ids = FullSearch::ExactMatch.ids_for(search_model, "honda", {account_id: @account.id})
    assert_includes ids, vehicle.id
  end

  def test_exact_match_without_source
    search_model = Class.new(Vehicle) do
      full_search do
        exact_match :make
        filter :account_id, required: true
      end
    end
    search_model.table_name = "vehicles"

    FullSearch::Index.rebuild!(search_model)

    vehicle = Vehicle.create!(account_id: @account.id, make: "Honda")

    ids = FullSearch::ExactMatch.ids_for(search_model, "Honda", {account_id: @account.id})
    assert_includes ids, vehicle.id
  end

  def test_multiple_exact_matches
    search_model = Class.new(Vehicle) do
      full_search do
        exact_match :make
        exact_match :license_plate
        filter :account_id, required: true
      end
    end
    search_model.table_name = "vehicles"
    FullSearch::Index.rebuild!(search_model)
    vehicle = Vehicle.create!(account_id: @account.id, make: "Honda", license_plate: "ABC-123")

    ids = FullSearch::ExactMatch.ids_for(search_model, "Honda", {account_id: @account.id})
    assert_includes ids, vehicle.id
  end

  def test_sql_exact_match_finds_record
    search_model = Class.new(Vehicle) do
      full_search do
        exact_match :make, source: -> { make&.upcase }, sql: "UPPER(make)"
        filter :account_id, required: true
      end
    end
    search_model.table_name = "vehicles"

    FullSearch::Index.rebuild!(search_model)

    vehicle = Vehicle.create!(account_id: @account.id, make: "Honda")

    ids = FullSearch::ExactMatch.ids_for(search_model, "HONDA", {account_id: @account.id})
    assert_includes ids, vehicle.id
  end

  def test_sql_exact_match_case_insensitive
    search_model = Class.new(Vehicle) do
      full_search do
        exact_match :make, source: -> { make&.upcase }, sql: "UPPER(make)"
        filter :account_id, required: true
      end
    end
    search_model.table_name = "vehicles"

    FullSearch::Index.rebuild!(search_model)

    vehicle = Vehicle.create!(account_id: @account.id, make: "honda")

    ids = FullSearch::ExactMatch.ids_for(search_model, "HONDA", {account_id: @account.id})
    assert_includes ids, vehicle.id
  end

  def test_exact_match_on_encrypted_column
    search_model = Class.new(Vehicle) do
      full_search do
        exact_match :license_plate, source: -> { license_plate&.to_s&.strip&.upcase }
        filter :account_id, required: true
      end
    end
    search_model.table_name = "vehicles"

    FullSearch::Index.rebuild!(search_model)

    vehicle = Vehicle.create!(account_id: @account.id, license_plate: "ABC-1234")

    ids = FullSearch::ExactMatch.ids_for(search_model, "ABC-1234", {account_id: @account.id})
    assert_includes ids, vehicle.id
  end
end
