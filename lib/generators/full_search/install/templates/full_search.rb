# frozen_string_literal: true

FullSearch.configure do |config|
  config.auto_rebuild_schema = Rails.env.local?

  config.stale_query_behavior = Rails.env.production? ? :log_and_fallback : :raise

  config.lock_rebuilds = true
end
