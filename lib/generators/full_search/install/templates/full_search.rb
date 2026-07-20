# frozen_string_literal: true

FullSearch.configure do |config|
  config.auto_rebuild_schema = Rails.env.local?

  config.auto_rebuild_on_stale_query = Rails.env.local?

  config.stale_query_behavior = Rails.env.production? ? :log_and_fallback : :raise

  config.lock_rebuilds = true

  # Reindex computed source: fields synchronously (false) or via background job (true).
  # Bulk imports should use FullSearch.bulk_import(Model) { ... } to defer reindexing.
  config.default_async_source_reindex = true
end
