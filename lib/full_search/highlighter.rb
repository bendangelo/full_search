# frozen_string_literal: true

module FullSearch
  class Highlighter
    def self.apply!(records, model, query)
      dsl = model.full_search_dsl
      config = dsl.highlight_config
      return records unless config

      match_expr = QueryParser.to_match_expression(QueryParser.parse(query))
      return records if match_expr.empty?

      table = FullSearch::Index.fts_table_name(model)

      content_cols = dsl.fields.map(&:name)
      return records if content_cols.empty?

      highlight_parts = content_cols.each_with_index.map do |col, idx|
        "highlight(#{table}, #{idx}, #{quote(config[:open_tag])}, #{quote(config[:close_tag])}) AS #{col}_snippet"
      end.join(", ")

      sql = <<~SQL
        SELECT rowid, #{highlight_parts}
        FROM #{table}
        WHERE #{table} MATCH #{quote(match_expr)}
      SQL

      rows = connection.execute(sql)

      snippets = rows.map do |r|
        [r["rowid"], content_cols.map { |col| r["#{col}_snippet"] }.compact.join(" ").strip]
      end.to_h

      records.each do |record|
        record.full_search_snippet = snippets[record.id]
      end

      records
    end

    private

    def self.connection
      ActiveRecord::Base.connection
    end

    def self.quote(value)
      connection.quote(value)
    end
  end
end
