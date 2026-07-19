# frozen_string_literal: true

require "minitest/autorun"
require "active_record"
require "full_search"

module Rails
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Encryption.configure(
  primary_key: "test-primary-key-123456789012",
  deterministic_key: "test-deterministic-key-1234567",
  key_derivation_salt: "test-salt-12345678"
)

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }
