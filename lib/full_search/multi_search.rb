# frozen_string_literal: true

module FullSearch
  class MultiSearch
    def self.call(query:, groups:)
      new(query: query, groups: groups).call
    end

    def initialize(query:, groups:)
      @query = query.to_s.strip
      @groups = groups
    end

    def call
      searched = groups.map do |group|
        model = fetch(group, :model)
        raise FullSearch::NotConfiguredError, "#{model} is not full_search configured" unless model.full_search_dsl

        filters = group[:filters] || {}
        limit = positive_integer(group[:limit], 8)
        offset = positive_integer(group[:offset], 0)
        raw_limit = limit + 1

        relation = model.full_search(
          query,
          filters: filters,
          limit: raw_limit,
          offset: offset,
          highlight: group[:highlight],
          highlight_fields: group[:highlight_fields]
        )

        relation = group[:scope].call(relation) if group[:scope]

        records = relation.to_a
        has_more = records.size > limit
        records = records.first(limit) if has_more

        group.slice(:key, :label, :icon, :model).merge(
          results: records,
          has_more: has_more,
          total_count: records.size
        )
      end

      {groups: searched, total_count: searched.sum { |g| g[:total_count] }}
    end

    private

    attr_reader :query, :groups

    def fetch(group, key)
      group.fetch(key) { fail ArgumentError, "Missing group key: #{key}" }
    end

    def positive_integer(value, default)
      value.to_i.positive? ? value.to_i : default
    end
  end

  class << self
    def multi_search(...)
      MultiSearch.call(...)
    end
  end
end
