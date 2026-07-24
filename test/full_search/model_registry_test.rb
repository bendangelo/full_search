# frozen_string_literal: true

require "test_helper"

class FullSearch::ModelRegistryTest < ActiveSupport::TestCase
  def setup
    @initial_models = FullSearch.models.dup
  end

  def teardown
    FullSearch.models.replace(@initial_models)
  end

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

  def test_sorted_models_returns_deterministic_order
    a_model = Class.new(Customer) {
      def self.name
        "AaaModel"
      end
      full_search { field :first_name }
    }
    a_model.table_name = "customers"
    b_model = Class.new(Vehicle) {
      def self.name
        "BbbModel"
      end
      full_search { field :make }
    }
    b_model.table_name = "vehicles"

    assert_equal ["customers", "vehicles"], FullSearch.sorted_models.map(&:table_name)
  ensure
    begin
      FullSearch.deregister_model(a_model)
    rescue
      nil
    end
    begin
      FullSearch.deregister_model(b_model)
    rescue
      nil
    end
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
