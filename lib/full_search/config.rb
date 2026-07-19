# frozen_string_literal: true

module FullSearch
  class Config
    attr_accessor :auto_rebuild_schema, :stale_query_behavior, :lock_rebuilds, :default_async_reindex, :default_tokenizer, :auto_rebuild_on_stale_query

    def initialize
      @auto_rebuild_schema = false
      @stale_query_behavior = :raise
      @lock_rebuilds = true
      @default_async_reindex = true
      @default_tokenizer = "unicode61"
      @auto_rebuild_on_stale_query = false
    end
  end

  class << self
    def config
      @config ||= Config.new
    end

    def configure
      yield config
    end
  end
end
