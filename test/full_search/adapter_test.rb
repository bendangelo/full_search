# frozen_string_literal: true

require "test_helper"

class FullSearch::AdapterTest < ActiveSupport::TestCase
  def test_raises_on_non_sqlite_adapter
    fake_model = Object.new
    def fake_model.connection
      @conn ||= Object.new.tap { |o|
        def o.adapter_name
          "PostgreSQL"
        end
      }
    end

    def fake_model.full_search_dsl
      nil
    end

    assert_raises(FullSearch::UnsupportedDatabaseError) do
      FullSearch::Index.ensure_table!(fake_model)
    end
  end

  def test_sqlite_adapter_does_not_raise
    assert_nothing_raised do
      model = Class.new(Customer) do
        full_search do
          field :first_name
          filter :account_id, required: true
        end
      end
      model.table_name = "customers"
      FullSearch::Index.ensure_table!(model)
    end
  end
end
