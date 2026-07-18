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
    FullSearch::Index.drop!(@model) rescue nil
  end

  def teardown
    Customer.delete_all
  end

  def test_ensure_table_creates_virtual_table
    FullSearch::Index.ensure_table!(@model)
    assert FullSearch::Index.send(:table_exists?, @model)
  end

  def test_rebuild_populates_rows
    account = Account.create!(name: "Acme")
    customer = @model.create!(account_id: account.id, first_name: "Sam", last_name: "Smith")
    FullSearch::Index.rebuild!(@model)

    rows = ActiveRecord::Base.connection.execute(
      "SELECT * FROM #{FullSearch::Index.fts_table_name(@model)}"
    )
    assert_equal 1, rows.count
  end
end
