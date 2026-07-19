# frozen_string_literal: true

module FullSearch
  class Highlighter
    def self.apply!(records, model, query)
      snippets = build_snippets(model, query)
      if snippets.values.all?(&:nil?) && records.any?
        snippets = manual_snippets(records, model, query)
      end
      records.each { |record| record.full_search_snippet = snippets[record.id] }
      records
    end

    def self.apply_fields!(records, model, query)
      fields = build_field_snippets(model, query)
      if fields.values.all?(&:empty?) && records.any?
        fields = manual_field_snippets(records, model, query)
      end
      exact_fields = exact_match_field_snippets(records, model, query)
      records.each do |record|
        merged = fields[record.id] || {}
        exact_fields.fetch(record.id, {}).each { |k, v| merged[k] ||= v }
        record.full_search_highlight_fields = merged
      end
      records
    end

    private

    def self.build_snippets(model, query)
      rows = highlight_rows(model, query)
      cols = model.full_search_dsl.fields.map(&:name)

      rows.to_h do |row|
        text = cols.map { |col| row["#{col}_snippet"] }.compact.join(" ").strip
        [row["rowid"], text.presence]
      end
    end

    def self.build_field_snippets(model, query)
      rows = highlight_rows(model, query)
      dsl = model.full_search_dsl
      fields = dsl.fields
      open_tag = (dsl.highlight_config || { open_tag: "<mark>" })[:open_tag]

      rows.to_h do |row|
        snippets = fields.each_with_object({}) do |field, hash|
          snippet = row["#{field.name}_snippet"].to_s.strip
          key = field.as || field.name
          hash[key] = snippet if snippet.include?(open_tag)
        end
        [row["rowid"], snippets]
      end
    end

    def self.compute_max_typos(query, dsl)
      return nil unless dsl.typo_tolerance?
      length = query.length
      min_length = dsl.typo_tolerance_min_term_length.to_i
      return nil if length < min_length
      return 2 if length >= 9
      1
    end

    def self.manual_snippets(records, model, query)
      dsl = model.full_search_dsl
      config = dsl.highlight_config || { open_tag: "<mark>", close_tag: "</mark>" }
      cols = dsl.fields.map(&:name)
      max_typos = compute_max_typos(query, dsl)

      records.to_h do |record|
        text = cols.map { |col| record.full_search_text_for(col).to_s }.join(" ").strip
        highlighted = manual_highlight(text, query, config, max_typos: max_typos)
        [record.id, highlighted.presence]
      end
    end

    def self.manual_field_snippets(records, model, query)
      dsl = model.full_search_dsl
      config = dsl.highlight_config || { open_tag: "<mark>", close_tag: "</mark>" }
      fields = dsl.fields
      max_typos = compute_max_typos(query, dsl)

      records.to_h do |record|
        snippets = fields.each_with_object({}) do |field, hash|
          value = record.full_search_text_for(field.name).to_s
          highlighted = manual_highlight(value, query, config, max_typos: max_typos)
          key = field.as || field.name
          hash[key] = highlighted if highlighted.include?(config[:open_tag])
        end
        [record.id, snippets]
      end
    end

    def self.exact_match_field_snippets(records, model, query)
      dsl = model.full_search_dsl
      return {} if dsl.exact_matches.empty?

      config = dsl.highlight_config || { open_tag: "<mark>", close_tag: "</mark>" }
      max_typos = compute_max_typos(query, dsl)

      records.to_h do |record|
        snippets = dsl.exact_matches.each_with_object({}) do |em, hash|
          value = exact_match_field_value(em, record)
          highlighted = manual_highlight(value.to_s, query, config, max_typos: max_typos)
          hash[em.name.to_s] = highlighted if highlighted.include?(config[:open_tag])
        end
        [record.id, snippets]
      end
    end

    def self.exact_match_field_value(em, record)
      if em.source
        record.instance_exec(&em.source)
      else
        record.public_send(em.name)
      end
    end

    def self.manual_highlight(text, query, config, max_typos: nil)
      return text if text.empty? || query.empty?

      open_tag = config[:open_tag]
      close_tag = config[:close_tag]
      escaped_query = Regexp.escape(query)

      if text.match?(/#{escaped_query}/i)
        return text.gsub(/#{escaped_query}/i, "#{open_tag}\\0#{close_tag}")
      end

      best = best_fuzzy_match(text, query, max_typos: max_typos)
      if best
        start_pos, end_pos = best
        return "#{text[0...start_pos]}#{open_tag}#{text[start_pos...end_pos]}#{close_tag}#{text[end_pos..]}"
      end

      text
    end

    def self.best_fuzzy_match(text, query, max_typos: nil)
      query_len = query.length
      text_len = text.length
      return nil if query_len == 0 || text_len == 0

      max_typos ||= max_allowed_typos(query_len)
      return nil if max_typos < 0

      best_score = max_typos + 1
      best_range = nil

      min_window = [1, query_len - max_typos].max
      max_window = [text_len, query_len + max_typos].min
      return nil if min_window > max_window

      (min_window..max_window).each do |window_len|
        (0..(text_len - window_len)).each do |start|
          substr = text[start, window_len]
          distance = damerau_levenshtein(query.downcase, substr.downcase)
          next if distance > max_typos

          if best_range.nil? || distance < best_score || (distance == best_score && window_len > (best_range[1] - best_range[0]))
            best_score = distance
            best_range = [start, start + window_len]
          end
        end
      end

      best_range
    end

    def self.max_allowed_typos(length)
      return -1 if length < 3
      return 2 if length >= 9
      1
    end

    def self.highlight_rows(model, query)
      dsl = model.full_search_dsl
      config = dsl.highlight_config || { open_tag: "<mark>", close_tag: "</mark>" }
      match_expr = QueryParser.to_match_expression(QueryParser.parse(query))
      return [] if match_expr.empty?

      table = FullSearch::Index.fts_table_name(model)
      cols = dsl.fields.map(&:name)
      return [] if cols.empty?

      highlight_parts = cols.each_with_index.map do |col, idx|
        "highlight(#{table}, #{idx}, #{quote(config[:open_tag])}, #{quote(config[:close_tag])}) AS #{col}_snippet"
      end.join(", ")

      sql = <<~SQL
        SELECT rowid, #{highlight_parts}
        FROM #{table}
        WHERE #{table} MATCH #{quote(match_expr)}
      SQL

      connection.execute(sql)
    end

    def self.connection
      ActiveRecord::Base.connection
    end

    def self.quote(value)
      connection.quote(value)
    end

    def self.damerau_levenshtein(a, b)
      a_len = a.length
      b_len = b.length
      return a_len if b_len == 0
      return b_len if a_len == 0

      d = Array.new(a_len + 1) { Array.new(b_len + 1, 0) }
      (0..a_len).each { |i| d[i][0] = i }
      (0..b_len).each { |j| d[0][j] = j }

      (1..a_len).each do |i|
        (1..b_len).each do |j|
          cost = a[i - 1] == b[j - 1] ? 0 : 1
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
  end
end
