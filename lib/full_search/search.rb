# frozen_string_literal: true

module FullSearch
  class Search
    attr_reader :model, :query, :filters, :include_soft_deleted, :limit, :offset, :highlight, :highlight_fields, :matching_strategy

    def initialize(model, query, filters:, include_soft_deleted:, limit:, offset:, highlight: false, highlight_fields: false, matching_strategy: nil)
      @model = model
      @query = query.to_s.strip
      @filters = filters
      @include_soft_deleted = include_soft_deleted
      @limit = limit
      @offset = offset
      @highlight = highlight
      @highlight_fields = highlight_fields
      @matching_strategy = matching_strategy
    end

    MIN_TERM_LENGTH = 3

    def relation
      validate_filter_keys!
      validate_required_filters!
      check_stale_config!

      return model.none if dsl.tokenize == "trigram" && query.length < MIN_TERM_LENGTH && !dsl.typo_tolerance?

      parsed = QueryParser.parse(query)
      exact_ids = ExactMatch.ids_for(model, query, filters)
      primary_ids = fts_match_ids(parsed)
      fallback_ids = (dsl.typo_tolerance? && matching_strategy != "all") ? trigram_match_ids(parsed, primary_ids) : []
      fuzzy_ids = (dsl.typo_tolerance? && matching_strategy != "all" && primary_ids.empty? && fallback_ids.empty?) ? fuzzy_match_ids(parsed) : []

      all_ids = (exact_ids + primary_ids + fallback_ids + fuzzy_ids).uniq
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
      stored = FullSearch::Index.stored_config_hash(model)
      return unless stored

      if stored != dsl.config_hash
        case FullSearch.config.stale_query_behavior
        when :raise
          raise ConfigChangedError, "FTS index for #{model.table_name} is stale; run full_search:rebuild"
        when :log_and_fallback
          Rails.logger.warn("[full_search] FTS index for #{model.table_name} is stale; results may be incomplete")
        end
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

      connection.execute("#{sql} #{filter_conditions}").map { |r| r["id"] }
    end

    def trigram_match_ids(parsed, primary_ids)
      return [] if primary_ids.any?

      match_expr = QueryParser.to_match_expression(parsed)
      return [] if match_expr.empty?

      term = parsed.last
      return [] if term.nil?

      if term.length < dsl.typo_tolerance_min_term_length.to_i
        return like_prefix_ids(term)
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

      connection.execute("#{sql} #{filter_conditions}").map { |r| r["id"] }
    end

    def like_prefix_ids(term)
      column_fields = dsl.fields.select { |f| f.source.nil? }
      source_fields = dsl.fields.select { |f| f.source }
      tbl = qt(model.table_name)

      soft_delete_clause = ""
      if dsl.soft_delete_column && !include_soft_deleted
        soft_delete_clause = "AND #{tbl}.#{qc(dsl.soft_delete_column)} IS NULL"
      end

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
          WHERE (#{like_conditions}) #{filter_conditions} #{soft_delete_clause}
        SQL

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

        sql = <<~SQL
          SELECT #{tbl}.id
          FROM #{fts_table}
          JOIN #{tbl} ON #{tbl}.id = #{fts_table}.rowid
          WHERE (#{like_conditions}) #{filter_conditions} #{soft_delete_clause}
        SQL

        ids = connection.execute(sql).map { |r| r["id"] }
      end

      ids
    end

    def fuzzy_match_ids(parsed)
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

      filter_conditions = filters.map do |name, value|
        "AND #{tbl}.#{qc(name)} = #{q(value)}"
      end.join(" ")

      conditions = column_fields.map do |field|
        "levenshtein(LOWER(#{tbl}.#{qc(field.name)}), #{q(term_str.downcase)}) <= #{max_typos}"
      end.join(" OR ")

      sql = <<~SQL
        SELECT #{tbl}.id
        FROM #{tbl}
        WHERE (#{conditions}) #{filter_conditions} #{soft_delete_clause}
      SQL

      connection.execute(sql).map { |r| r["id"] }
    end

    def max_allowed_typos(length)
      min_length = dsl.typo_tolerance_min_term_length.to_i
      return -1 if length < min_length
      return 2 if length >= 9
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
        func.result = damerau_levenshtein(s1.to_s, s2.to_s)
      end
      @levenshtein_registered = true
    end

    def damerau_levenshtein(a, b)
      a_len = a.length
      b_len = b.length
      return a_len if b_len == 0
      return b_len if a_len == 0

      d = Array.new(a_len + 1) { Array.new(b_len + 1, 0) }
      (0..a_len).each { |i| d[i][0] = i }
      (0..b_len).each { |j| d[0][j] = j }

      (1..a_len).each do |i|
        (1..b_len).each do |j|
          cost = (a[i - 1] == b[j - 1]) ? 0 : 1
          d[i][j] = [
            d[i - 1][j] + 1,
            d[i][j - 1] + 1,
            d[i - 1][j - 1] + cost
          ].min

          if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]
            d[i][j] = [d[i][j], d[i - 2][j - 2] + 1].min
          end
        end
      end

      d[a_len][b_len]
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

    def q(value)
      connection.quote(value)
    end

    def qt(name)
      connection.quote_table_name(name)
    end

    def qc(name)
      connection.quote_column_name(name)
    end
  end
end
