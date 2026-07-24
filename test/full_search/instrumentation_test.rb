# frozen_string_literal: true

require "test_helper"

class FullSearch::InstrumentationTest < ActiveSupport::TestCase
  def test_emits_query_event
    model = Class.new(Customer) do
      def self.name
        "InstrumentedCustomer"
      end
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"

    events = []
    subscriber = ActiveSupport::Notifications.subscribe("full_search.query") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    account = Account.create!(name: "Acme")
    model.create!(account_id: account.id, first_name: "Sam")
    FullSearch::Index.rebuild!(model)
    model.full_search("Sam", filters: {account_id: account.id}).to_a

    assert_equal 1, events.size
    assert_equal "InstrumentedCustomer", events.first.payload[:model]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    begin
      FullSearch::Index.drop!(model)
    rescue
      nil
    end
    Customer.delete_all
    Account.delete_all
  end

  def test_emits_rebuild_event
    model = Class.new(Customer) do
      def self.name
        "InstrumentedRebuild"
      end
      full_search do
        field :first_name
        filter :account_id, required: true
      end
    end
    model.table_name = "customers"

    events = []
    subscriber = ActiveSupport::Notifications.subscribe("full_search.rebuild") do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    FullSearch::Index.rebuild!(model)

    assert_equal 1, events.size
    assert_equal "InstrumentedRebuild", events.first.payload[:model]
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
    begin
      FullSearch::Index.drop!(model)
    rescue
      nil
    end
    Customer.delete_all
    Account.delete_all
  end
end
