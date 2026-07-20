# frozen_string_literal: true

require "test_helper"
require "active_job/test_helper"

ActiveJob::Base.queue_adapter = :inline

class FullSearch::CallbacksTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def test_source_field_reindex_is_async_by_default
    ActiveJob::Base.queue_adapter = :test
    model = Class.new(Customer) do
      def self.name
        "AsyncSourceCustomer"
      end
      full_search do
        field :computed, source: -> { "customer_#{first_name}" }
        filter :account_id, required: true
      end
    end
    Object.const_set(:AsyncSourceCustomer, model)
    model.table_name = "customers"
    FullSearch::Index.rebuild!(model)

    account = Account.create!(name: "Acme")
    assert_enqueued_jobs 1 do
      model.create!(account_id: account.id, first_name: "Sam")
    end
  ensure
    begin
      FullSearch::Index.drop!(model)
    rescue
      nil
    end
    Object.send(:remove_const, :AsyncSourceCustomer) if Object.const_defined?(:AsyncSourceCustomer)
  end

  def test_source_field_reindex_is_sync_when_async_source_false
    ActiveJob::Base.queue_adapter = :inline
    model = Class.new(Customer) do
      def self.name
        "SyncSourceCustomer"
      end
      full_search do
        field :computed, source: -> { "customer_#{first_name}" }, async_source: false
        filter :account_id, required: true
      end
    end
    Object.const_set(:SyncSourceCustomer, model)
    model.table_name = "customers"
    FullSearch::Index.rebuild!(model)

    account = Account.create!(name: "Acme")
    customer = model.create!(account_id: account.id, first_name: "Sam")

    row = ActiveRecord::Base.connection.execute(
      "SELECT computed FROM #{FullSearch::Index.fts_table_name(model)} WHERE rowid = #{customer.id}"
    ).first
    assert_equal "customer_Sam", row["computed"]
  ensure
    begin
      FullSearch::Index.drop!(model)
    rescue
      nil
    end
    Object.send(:remove_const, :SyncSourceCustomer) if Object.const_defined?(:SyncSourceCustomer)
  end
end

