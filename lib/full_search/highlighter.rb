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
      if fields.empty? && records.any?
        fields = manual_field_snippets(records, model, query)
      end
      records.each { |record| record.full_search_highlight_fields = fields[record.id] || {} }
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
      cols = dsl.fields.map(&:name)
      open_tag = (dsl.highlight_config || { open_tag: "<mark>" })[:open_tag]

      rows.to_h do |row|
        snippets = cols.each_with_object({}) do |col, hash|
          snippet = row["#{col}_snippet"].to_s.strip
          hash[col.to_s] = snippet if snippet.include?(open_tag)
        end
        [row["rowid"], snippets]
      end
    end

    def self.manual_snippets(records, model, query)
      dsl = model.full_search_dsl
      config = dsl.highlight_config || { open_tag: "<mark>", close_tag: "</mark>" }
        cols = dsl.fields.map(&:name)

        records.to_h do |record|
          text = cols.map { |col| record.full_search_text_for(col).to_s }.join(" ").strip
          highlighted = manual_highlight(text, query, config)
          [record.id, highlighted.presence]
        end
    end

    def self.manual_field_snippets(records, model, query)
      dsl = model.full_search_dsl
      config = dsl.highlight_config || { open_tag: "<mark>", close_tag: "</mark>" }
      cols = dsl.fields.map(&:name)

      records.to_h do |record|
        snippets = cols.each_with_object({}) do |col, hash|
          value = record.full_search_text_for(col).to_s
          highlighted = manual_highlight(value, query, config)
          hash[col.to_s] = highlighted if highlighted.include?(config[:open_tag])
        end
        [record.id, snippets]
      end
    end

    def self.manual_highlight(text, query, config)
      return text if text.empty? || query.empty?
      text.gsub(/#{Regexp.escape(query)}/i, "#{config[:open_tag]}\\0#{config[:close_tag]}")
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
  end
end
