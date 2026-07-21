# frozen_string_literal: true

module FullSearch
  class IndexCache
    def self.with_cache
      already_cached = !Thread.current[:full_search_index_cache].nil?
      Thread.current[:full_search_index_cache] ||= {}
      yield
    ensure
      Thread.current[:full_search_index_cache] = nil unless already_cached
    end

    def self.clear!
      Thread.current[:full_search_index_cache] = nil
    end

    def self.fetch(key)
      cache = Thread.current[:full_search_index_cache]
      return yield unless cache
      return cache[key] if cache.key?(key)
      cache[key] = yield
    end
  end
end
