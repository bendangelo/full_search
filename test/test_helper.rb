# frozen_string_literal: true

require "minitest/autorun"
require "active_record"
require "full_search"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }
