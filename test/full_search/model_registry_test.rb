# frozen_string_literal: true

require "test_helper"

class FullSearch::ModelRegistryTest < ActiveSupport::TestCase
  def test_models_is_a_set_of_unique_classes
    assert_kind_of Set, FullSearch.models
  end

  def test_deregister_model
    klass = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    klass.table_name = "customers"
    FullSearch.register_model(klass)
    assert_includes FullSearch.models, klass
    FullSearch.deregister_model(klass)
    refute_includes FullSearch.models, klass
  end

  def test_registering_same_class_twice_is_idempotent
    klass = Class.new(Customer) do
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    klass.table_name = "customers"
    FullSearch.register_model(klass)
    size_before = FullSearch.models.size
    FullSearch.register_model(klass)
    assert_equal size_before, FullSearch.models.size
  end
end
