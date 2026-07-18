# frozen_string_literal: true

module FullSearch
  class Search
    attr_reader :model, :query, :filters, :include_soft_deleted, :limit, :offset, :highlight

    def initialize(model, query, filters:, include_soft_deleted:, limit:, offset:, highlight: false)
      @model = model
      @query = query.to_s.strip
      @filters = filters
      @include_soft_deleted = include_soft_deleted
      @limit = limit
      @offset = offset
      @highlight = highlight
    end

    def relation
      validate_required_filters!

      parsed = QueryParser.parse(query)
      exact_ids = ExactMatch.ids_for(model, query, filters)
      primary_ids = fts_match_ids(parsed)
      fallback_ids = dsl.typo_tolerance? ? trigram_match_ids(parsed, primary_ids) : []

      all_ids = (exact_ids + primary_ids + fallback_ids).uniq
      return model.none if all_ids.empty?

      rel = model.where(id: all_ids)
      rel = rel.where(model.arel_table[dsl.soft_delete_column].eq(nil)) if dsl.soft_delete_column && !include_soft_deleted
      rel = rel.limit(limit) if limit
      rel = rel.offset(offset) if offset

      order_sql = case_clause(all_ids)
      rel = rel.order(Arel.sql(order_sql))

      if highlight
        Highlighter.apply!(rel.to_a, model, query)
      else
        rel
      end
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

    def fts_match_ids(parsed)
      return [] if query.empty?

      match_expr = QueryParser.to_match_expression(parsed)
      fts_table = FullSearch::Index.fts_table_name(model)

      sql = <<~SQL
        SELECT #{model.table_name}.id
        FROM #{fts_table}
        JOIN #{model.table_name} ON #{model.table_name}.id = #{fts_table}.rowid
        WHERE #{fts_table} MATCH #{connection.quote(match_expr)}
      SQL

      filter_conditions = filters.map do |name, value|
        "AND #{fts_table}.#{name} = #{connection.quote(value)}"
      end.join(" ")

      connection.execute("#{sql} #{filter_conditions}").map { |r| r["id"] }
    end

    def trigram_match_ids(parsed, primary_ids)
      return [] if primary_ids.any?

      match_expr = QueryParser.to_match_expression(parsed)
      return [] if match_expr.empty?

      term = parsed.last rescue nil
      return [] if term.nil? || term.length < dsl.typo_tolerance_min_term_length.to_i

      trigram_table = FullSearch::Index.trigram_table_name(model)

      sql = <<~SQL
        SELECT #{model.table_name}.id
        FROM #{trigram_table}
        JOIN #{model.table_name} ON #{model.table_name}.id = #{trigram_table}.rowid
        WHERE #{trigram_table} MATCH #{connection.quote(match_expr)}
      SQL

      filter_conditions = filters.map do |name, value|
        "AND #{trigram_table}.#{name} = #{connection.quote(value)}"
      end.join(" ")

      connection.execute("#{sql} #{filter_conditions}").map { |r| r["id"] }
    end

    def bare_term?(parsed)
      parsed.is_a?(Array) && parsed.size == 2 && parsed.first == :term
    end

    def case_clause(ids)
      "CASE id #{ids.map.with_index { |id, i| "WHEN #{id} THEN #{i}" }.join(" ")} END"
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end
