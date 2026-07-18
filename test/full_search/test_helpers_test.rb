# frozen_string_literal: true

require "test_helper"

class FullSearch::TestHelpersTest < ActiveSupport::TestCase
  include FullSearch::TestHelpers

  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"
  end

  def teardown
    FullSearch::Index.drop!(@model) rescue nil
  end

  def test_rebuild_creates_index
    rebuild_full_search_index(@model)
    assert FullSearch::Index.send(:table_exists?, @model)
  end
end
