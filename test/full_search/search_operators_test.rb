# frozen_string_literal: true

require "test_helper"

class FullSearch::SearchOperatorsTest < ActiveSupport::TestCase
  def setup
    @model = Class.new(Customer) do
      full_search do
        field :first_name, weight: 5
        field :last_name, weight: 5
        filter :account_id, required: true
      end
    end
    @model.table_name = "customers"
    @account = Account.create!(name: "Acme")
    FullSearch::Index.rebuild!(@model)
  end

  def teardown
    Customer.delete_all
  end

  def test_phrase_search
    customer = @model.create!(account_id: @account.id, first_name: "Samantha Jones", last_name: "")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search('"Samantha Jones"', filters: { account_id: @account.id })
    assert_includes results.to_a, customer
  end

  def test_exclusion_search
    sam = @model.create!(account_id: @account.id, first_name: "Sam", last_name: "Smith")
    cam = @model.create!(account_id: @account.id, first_name: "Cam", last_name: "Smith")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("Smith -Cam", filters: { account_id: @account.id })
    assert_includes results.to_a, sam
    refute_includes results.to_a, cam
  end

  def test_or_search
    sam = @model.create!(account_id: @account.id, first_name: "Sam")
    jane = @model.create!(account_id: @account.id, first_name: "Jane")
    FullSearch::Index.rebuild!(@model)

    results = @model.full_search("Sam OR Jane", filters: { account_id: @account.id })
    assert_includes results.to_a, sam
    assert_includes results.to_a, jane
  end
end
