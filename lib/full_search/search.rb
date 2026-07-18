# frozen_string_literal: true

module FullSearch
  class Search
    attr_reader :model, :query, :filters, :include_soft_deleted, :limit, :offset

    def initialize(model, query, filters:, include_soft_deleted:, limit:, offset:)
      @model = model
      @query = query.to_s.strip
      @filters = filters
      @include_soft_deleted = include_soft_deleted
      @limit = limit
      @offset = offset
    end

    def relation
      validate_required_filters!

      exact_ids = ExactMatch.ids_for(model, query, filters)
      fts_ids = fts_match_ids

      all_ids = (exact_ids + fts_ids).uniq
      return model.none if all_ids.empty?

      rel = model.where(id: all_ids)
      rel = rel.where(model.arel_table[dsl.soft_delete_column].eq(nil)) if dsl.soft_delete_column && !include_soft_deleted
      rel = rel.limit(limit) if limit
      rel = rel.offset(offset) if offset

      order_sql = case_clause(all_ids)
      rel.order(Arel.sql(order_sql))
    end

    private

    def dsl
      model.full_search_dsl
    end

    def validate_required_filters!
      dsl.filters.each do |filter|
        next unless filter.required
        raise MissingRequiredFilterError, "Missing required filter: #{filter.name}" unless filters.key?(filter.name.to_sym) || filters.key?(filter.name)
      end
    end

    def fts_match_ids
      return [] if query.length < 3

      terms = query.split.map { |t| %("#{t.gsub('"', '""')}"*) }.join(" AND ")
      sql = <<~SQL
        SELECT #{model.table_name}.id
        FROM #{FullSearch::Index.fts_table_name(model)}
        JOIN #{model.table_name} ON #{model.table_name}.id = #{FullSearch::Index.fts_table_name(model)}.rowid
        WHERE #{FullSearch::Index.fts_table_name(model)} MATCH #{connection.quote(terms)}
      SQL

      filter_conditions = filters.map do |name, value|
        "AND #{FullSearch::Index.fts_table_name(model)}.#{name} = #{connection.quote(value)}"
      end.join(" ")

      connection.execute("#{sql} #{filter_conditions}").map { |r| r["id"] }
    end

    def case_clause(ids)
      "CASE id #{ids.map.with_index { |id, i| "WHEN #{id} THEN #{i}" }.join(" ")} END"
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end
