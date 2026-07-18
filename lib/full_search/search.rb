# frozen_string_literal: true

module FullSearch
  class Search
    attr_reader :model, :query, :filters, :include_soft_deleted, :limit, :offset, :highlight, :highlight_fields

    def initialize(model, query, filters:, include_soft_deleted:, limit:, offset:, highlight: false, highlight_fields: false)
      @model = model
      @query = query.to_s.strip
      @filters = filters
      @include_soft_deleted = include_soft_deleted
      @limit = limit
      @offset = offset
      @highlight = highlight
      @highlight_fields = highlight_fields
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

      rel = apply_ranking(rel, all_ids, exact_ids)

      if highlight
        Highlighter.apply!(rel.to_a, model, query)
      elsif highlight_fields
        Highlighter.apply_fields!(rel.to_a, model, query)
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
      return [] if term.nil?

      if term.length < dsl.typo_tolerance_min_term_length.to_i
        return like_prefix_ids(term)
      end

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

    def like_prefix_ids(term)
      column_fields = dsl.fields.select { |f| f.source.nil? }
      return [] if column_fields.empty?

      like_conditions = column_fields.map do |field|
        "#{connection.quote_table_name(model.table_name)}.#{connection.quote_column_name(field.name)} LIKE #{connection.quote("#{term}%")}"
      end.join(" OR ")

      sql = <<~SQL
        SELECT #{model.table_name}.id
        FROM #{model.table_name}
        WHERE (#{like_conditions})
      SQL

      filter_conditions = filters.map do |name, value|
        "AND #{model.table_name}.#{name} = #{connection.quote(value)}"
      end.join(" ")

      connection.execute("#{sql} #{filter_conditions}").map { |r| r["id"] }
    end

    def apply_ranking(rel, all_ids, exact_ids)
      return rel if all_ids.empty?

      order_parts = []

      if exact_ids.any?
        order_parts << "CASE #{model.table_name}.id #{exact_ids.map { |id| "WHEN #{id} THEN 0" }.join(" ")} ELSE 1 END"
      end

      fts_table = FullSearch::Index.fts_table_name(model)
      match_expr = QueryParser.to_match_expression(QueryParser.parse(query))

      rank_subquery = <<~SQL
        SELECT rowid, rank
        FROM #{fts_table}
        WHERE #{fts_table} MATCH #{connection.quote(match_expr)}
      SQL

      rel = rel
        .select("#{model.table_name}.*, fts_rank.rank AS full_search_rank")
        .joins("LEFT JOIN (#{rank_subquery}) AS fts_rank ON fts_rank.rowid = #{model.table_name}.id")

      order_parts << "COALESCE(fts_rank.rank, 1)"

      dsl.rank_bys.each do |rank_by|
        col = "#{connection.quote_table_name(model.table_name)}.#{connection.quote_column_name(rank_by.column)}"
        order_parts << "#{col} #{rank_by.direction.to_s.upcase} NULLS LAST"
      end

      rel.order(Arel.sql(order_parts.join(", ")))
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end
