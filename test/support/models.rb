# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :accounts, force: true do |t|
    t.string :name
  end

  create_table :customers, force: true do |t|
    t.references :account, null: false
    t.string :first_name
    t.string :last_name
    t.string :company_name
    t.string :fleet_identifier
    t.integer :customer_type, default: 0
    t.datetime :discarded_at
  end

  create_table :vehicles, force: true do |t|
    t.references :account, null: false
    t.references :customer
    t.string :make
    t.string :model
    t.string :vin
    t.string :license_plate
    t.integer :year
    t.integer :vehicle_type, default: 0
    t.datetime :discarded_at
  end
end

class Account < ActiveRecord::Base
  has_many :customers
  has_many :vehicles
end

class Customer < ActiveRecord::Base
  has_many :vehicles
end

class Vehicle < ActiveRecord::Base
  belongs_to :customer, optional: true
end
