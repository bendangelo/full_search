# frozen_string_literal: true

require "test_helper"

class FullSearch::DslTest < ActiveSupport::TestCase
  def setup
    @dsl = FullSearch::Dsl.new(Customer)
  end

  def test_field_records_declaration
    @dsl.field :first_name, weight: 5
    assert_equal 1, @dsl.fields.size
    assert_equal "first_name", @dsl.fields.first.name
    assert_equal 5, @dsl.fields.first.weight
  end

  def test_exact_match_records_declaration
    @dsl.exact_match :vin, source: -> { vin }
    assert_equal "vin", @dsl.exact_matches.first.name
  end

  def test_filter_records_required_flag
    @dsl.filter :account_id, required: true
    assert @dsl.filters.first.required
  end

  def test_soft_delete_column
    @dsl.soft_delete_column :discarded_at
    assert_equal "discarded_at", @dsl.soft_delete_column
  end

  def test_invalid_field_name_raises
    assert_raises(FullSearch::InvalidFieldError) { @dsl.field "bad; name" }
  end

  def test_config_hash_changes_when_source_proc_changes
    dsl1 = FullSearch::Dsl.new(Customer)
    dsl1.field :name_search, source: -> { name }, version: 1

    dsl2 = FullSearch::Dsl.new(Customer)
    dsl2.field :name_search, source: -> { name&.upcase }, version: 2

    refute_equal dsl1.config_hash, dsl2.config_hash
  end

  def test_config_hash_differs_when_version_differs
    dsl1 = FullSearch::Dsl.new(Customer)
    dsl1.field :name, source: -> { name }, version: 1

    dsl2 = FullSearch::Dsl.new(Customer)
    dsl2.field :name, source: -> { name }, version: 2

    refute_equal dsl1.config_hash, dsl2.config_hash
  end

  def test_config_hash_same_when_version_nil
    dsl1 = FullSearch::Dsl.new(Customer)
    dsl1.field :name, source: -> { name }

    dsl2 = FullSearch::Dsl.new(Customer)
    dsl2.field :name, source: -> { name }

    assert_equal dsl1.config_hash, dsl2.config_hash
  end

  def test_duplicate_field_name_raises
    @dsl.field :first_name
    assert_raises(FullSearch::InvalidFieldError) do
      @dsl.field :first_name
    end
  end

  def test_duplicate_filter_name_raises
    @dsl.filter :account_id
    assert_raises(FullSearch::InvalidFieldError) do
      @dsl.filter :account_id
    end
  end

  def test_field_and_filter_same_name_raises
    @dsl.field :account_id
    assert_raises(FullSearch::InvalidFieldError) do
      @dsl.filter :account_id
    end
  end
end
