# frozen_string_literal: true

module FullSearch
  class Search
    attr_reader :model, :query, :filters, :include_soft_deleted, :limit, :offset, :highlight, :highlight_fields, :matching_strategy, :per_strategy_limit, :scope, :includes

    def initialize(model, query, filters:, include_soft_deleted:, limit:, offset:, highlight: false, highlight_fields: false, matching_strategy: nil, per_strategy_limit: nil, scope: nil, includes: nil)
      @model = model
      @query = query.to_s.strip
      @filters = filters
      @include_soft_deleted = include_soft_deleted
      @limit = limit
      @offset = offset
      @highlight = highlight
      @highlight_fields = highlight_fields
      @matching_strategy = matching_strategy
      @per_strategy_limit = per_strategy_limit
      @scope = scope
      @includes = includes
    end

    MIN_TERM_LENGTH = FullSearch::Constants::MIN_TERM_LENGTH

    def relation
      FullSearch::Instrumentation.instrument("query", model: model.name, query: query) do
        validate_filter_keys!
        validate_required_filters!
        check_stale_config!

        return model.none if dsl.tokenize == "trigram" && query.length < MIN_TERM_LENGTH && !dsl.typo_tolerance?

        parsed = QueryParser.parse(query)
        exact_ids = ExactMatch.ids_for(model, query, filters)
        primary_ids = fts_match_ids(parsed)
        fallback_ids = (dsl.typo_tolerance? && matching_strategy != "all") ? trigram_match_ids(parsed, primary_ids, candidate_limit: per_strategy_limit) : []
        fuzzy_ids = (dsl.typo_tolerance? && matching_strategy != "all" && primary_ids.empty? && fallback_ids.empty?) ? fuzzy_match_ids(parsed, candidate_limit: per_strategy_limit) : []

        all_ids = (exact_ids + primary_ids + fallback_ids + fuzzy_ids).uniq
        return model.none if all_ids.empty?

        rel = model.where(id: all_ids)
        rel = rel.where(model.arel_table[dsl.soft_delete_column].eq(nil)) if dsl.soft_delete_column && !include_soft_deleted
        rel = apply_ranking(rel, all_ids, exact_ids)
        rel = scope.call(rel) if scope
        rel = rel.limit(limit) if limit
        rel = rel.offset(offset) if offset
        rel = rel.includes(includes) if includes

        if highlight
          records = rel.to_a
          Highlighter.apply!(records, model, query, record_ids: records.map(&:id))
          records
        elsif highlight_fields
          records = rel.to_a
          Highlighter.apply_fields!(records, model, query, record_ids: records.map(&:id))
          records
        else
          rel
        end
      end
    end

    private

    def dsl
      model.full_search_dsl
    end

    def validate_filter_keys!
      allowed = dsl.filters.map(&:name).to_set
      filters.each_key do |key|
        unless allowed.include?(key.to_s)
          raise UnknownFilterError, "Unknown filter: #{key}"
        end
      end
    end

    def validate_required_filters!
      dsl.filters.each do |filter|
        next unless filter.required
        raise MissingRequiredFilterError, "Missing required filter: #{filter.name}" unless filters.key?(filter.name.to_sym) || filters.key?(filter.name)
      end
    end

    def check_stale_config!
      if FullSearch::Index.missing_table?(model)
        raise MissingTableError, "FTS table `#{FullSearch::Index.fts_table_name(model)}` does not exist. Run `bin/rails full_search:prepare` to create it."
      end

      stored = begin
        FullSearch::Index.stored_config_hash(model)
      rescue
        nil
      end
      return unless stored

      return if stored == dsl.config_hash

      if FullSearch.config.auto_rebuild_on_stale_query
        FullSearch::Index.rebuild_if_needed!(model)
        return
      end

      case FullSearch.config.stale_query_behavior
      when :raise
        raise ConfigChangedError, "FTS index for #{model.table_name} is stale; run full_search:rebuild"
      when :log_and_fallback
        Rails.logger.warn("[full_search] FTS index for #{model.table_name} is stale; results may be incomplete")
      end
    end

    def fts_match_ids(parsed)
      return [] if query.empty?

      match_expr = QueryParser.to_match_expression(parsed)
      fts_table = qt(FullSearch::Index.fts_table_name(model))
      tbl = qt(model.table_name)

      sql = <<~SQL
        SELECT #{tbl}.id
        FROM #{fts_table}
        JOIN #{tbl} ON #{tbl}.id = #{fts_table}.rowid
        WHERE #{fts_table} MATCH #{q(match_expr)}
      SQL

      filter_conditions = filters.map do |name, value|
        "AND #{fts_table}.#{qc(name)} = #{q(value)}"
      end.join(" ")

      indexed_filter = dsl.conditional_index? ? " AND #{fts_table}.indexed = '1'" : ""

      connection.execute("#{sql} #{filter_conditions}#{indexed_filter}").map { |r| r["id"] }
    end

    def trigram_match_ids(parsed, primary_ids, candidate_limit: nil)
      return [] if primary_ids.any?

      match_expr = QueryParser.to_match_expression(parsed)
      return [] if match_expr.empty?

      term = parsed.last
      return [] if term.nil?

      if term.length < dsl.typo_tolerance_min_term_length.to_i
        return [] if term.length < dsl.min_like_prefix_length
        return like_prefix_ids(term, candidate_limit: candidate_limit)
      end

      trigram_table = qt(FullSearch::Index.trigram_table_name(model))
      tbl = qt(model.table_name)

      sql = <<~SQL
        SELECT #{tbl}.id
        FROM #{trigram_table}
        JOIN #{tbl} ON #{tbl}.id = #{trigram_table}.rowid
        WHERE #{trigram_table} MATCH #{q(match_expr)}
      SQL

      filter_conditions = filters.map do |name, value|
        "AND #{trigram_table}.#{qc(name)} = #{q(value)}"
      end.join(" ")

      indexed_filter = dsl.conditional_index? ? " AND #{trigram_table}.indexed = '1'" : ""

      sql += filter_conditions + indexed_filter
      order_and_limit!(sql, tbl, candidate_limit)
      connection.execute(sql).map { |r| r["id"] }
    end

    def like_prefix_ids(term, candidate_limit: nil)
      return [] if term.to_s.length < dsl.min_like_prefix_length

      column_fields = dsl.fields.select { |f| f.source.nil? }
      source_fields = dsl.fields.select { |f| f.source }
      tbl = qt(model.table_name)

      soft_delete_clause = ""
      if dsl.soft_delete_column && !include_soft_deleted
        soft_delete_clause = "AND #{tbl}.#{qc(dsl.soft_delete_column)} IS NULL"
      end

      indexed_clause = dsl.conditional_index? ? "AND (#{dsl.index_if_sql}) " : ""

      ids = []

      if column_fields.any?
        like_conditions = column_fields.map do |field|
          "#{tbl}.#{qc(field.name)} LIKE #{q("#{term}%")}"
        end.join(" OR ")

        filter_conditions = filters.map do |name, value|
          "AND #{tbl}.#{qc(name)} = #{q(value)}"
        end.join(" ")

        sql = <<~SQL
          SELECT #{tbl}.id
          FROM #{tbl}
          WHERE (#{like_conditions}) #{filter_conditions} #{soft_delete_clause} #{indexed_clause}
        SQL

        order_and_limit!(sql, tbl, candidate_limit)
        ids = connection.execute(sql).map { |r| r["id"] }
        return ids if ids.any?
      end

      if source_fields.any?
        fts_table = qt(FullSearch::Index.fts_table_name(model))
        like_conditions = source_fields.map do |field|
          "#{fts_table}.#{qc(field.name)} LIKE #{q("#{term}%")}"
        end.join(" OR ")

        filter_conditions = filters.map do |name, value|
          "AND #{fts_table}.#{qc(name)} = #{q(value)}"
        end.join(" ")

        fts_indexed = dsl.conditional_index? ? " AND #{fts_table}.indexed = '1'" : ""

        sql = <<~SQL
          SELECT #{tbl}.id
          FROM #{fts_table}
          JOIN #{tbl} ON #{tbl}.id = #{fts_table}.rowid
          WHERE (#{like_conditions}) #{filter_conditions} #{soft_delete_clause}#{fts_indexed}
        SQL

        order_and_limit!(sql, tbl, candidate_limit)
        ids = connection.execute(sql).map { |r| r["id"] }
      end

      ids
    end

    def fuzzy_match_ids(parsed, candidate_limit: nil)
      term = parsed.last
      return [] if term.nil?

      term_str = term.is_a?(Array) ? extract_last_term_string(term) : term.to_s
      return [] if term_str.empty?

      max_typos = max_allowed_typos(term_str.length)
      return [] if max_typos < 0

      column_fields = dsl.fields.select { |f| f.source.nil? }
      return [] if column_fields.empty?

      register_levenshtein!
      tbl = qt(model.table_name)

      soft_delete_clause = ""
      if dsl.soft_delete_column && !include_soft_deleted
        soft_delete_clause = "AND #{tbl}.#{qc(dsl.soft_delete_column)} IS NULL"
      end

      indexed_clause = dsl.conditional_index? ? "AND (#{dsl.index_if_sql}) " : ""

      filter_conditions = filters.map do |name, value|
        "AND #{tbl}.#{qc(name)} = #{q(value)}"
      end.join(" ")

      conditions = column_fields.map do |field|
        "levenshtein(LOWER(#{tbl}.#{qc(field.name)}), #{q(term_str.downcase)}) <= #{max_typos}"
      end.join(" OR ")

      sql = <<~SQL
        SELECT #{tbl}.id
        FROM #{tbl}
        WHERE (#{conditions}) #{filter_conditions} #{soft_delete_clause} #{indexed_clause}
      SQL

      order_and_limit!(sql, tbl, candidate_limit)
      connection.execute(sql).map { |r| r["id"] }
    end

    def order_and_limit!(sql, tbl, candidate_limit)
      order_parts = dsl.rank_bys.map do |rank_by|
        "#{tbl}.#{qc(rank_by.column)} #{rank_by.direction.to_s.upcase} NULLS LAST"
      end
      sql << " ORDER BY #{order_parts.join(", ")}" if order_parts.any?
      sql << " LIMIT #{candidate_limit.to_i}" if candidate_limit
    end

    def max_allowed_typos(length)
      min_length = dsl.typo_tolerance_min_term_length.to_i
      return -1 if length < min_length
      return 2 if length >= FullSearch::Constants::TWO_TYPO_MIN_LENGTH
      1
    end

    def extract_last_term_string(terms)
      last = terms.last
      last.is_a?(Array) ? last.last.to_s : last.to_s
    end

    def register_levenshtein!
      return if @levenshtein_registered

      raw = connection.raw_connection
      raw.create_function("levenshtein", 2) do |func, s1, s2|
        func.result = Distance.damerau_levenshtein(s1.to_s, s2.to_s)
      end
      @levenshtein_registered = true
    end

    def apply_ranking(rel, all_ids, exact_ids)
      return rel if all_ids.empty?

      order_parts = []
      tbl = qt(model.table_name)

      if exact_ids.any?
        order_parts << "CASE #{tbl}.id #{exact_ids.map { |id| "WHEN #{q(id)} THEN 0" }.join(" ")} ELSE 1 END"
      end

      fts_table = qt(FullSearch::Index.fts_table_name(model))
      match_expr = QueryParser.to_match_expression(QueryParser.parse(query))

      rank_subquery = <<~SQL
        SELECT rowid, rank
        FROM #{fts_table}
        WHERE #{fts_table} MATCH #{q(match_expr)}
      SQL

      rel = rel
        .select("#{tbl}.*, fts_rank.rank AS full_search_rank")
        .joins("LEFT JOIN (#{rank_subquery}) AS fts_rank ON fts_rank.rowid = #{tbl}.id")

      order_parts << "COALESCE(fts_rank.rank, 1)"

      dsl.rank_bys.each do |rank_by|
        col = "#{tbl}.#{qc(rank_by.column)}"
        order_parts << "#{col} #{rank_by.direction.to_s.upcase} NULLS LAST"
      end

      rel.order(Arel.sql(order_parts.join(", ")))
    end

    def connection
      model.connection
    rescue NoMethodError
      ActiveRecord::Base.connection
    end

    include Quoting
  end
end
