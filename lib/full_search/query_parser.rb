# frozen_string_literal: true

require "strscan"

module FullSearch
  module QueryParser
    Token = Data.define(:type, :value)

    MAX_QUERY_LENGTH = 255

    class << self
      def parse(query)
        query = query.to_s.strip
        validate!(query)
        tokens = tokenize(query)
        return [] if tokens.empty?

        or_clauses = split_or(tokens)

        if or_clauses.size == 1
          parse_and_clause(or_clauses.first)
        else
          [:or, or_clauses.map { |clause| parse_and_clause(clause) }]
        end
      end

      def to_match_expression(parsed)
        return '""' if parsed.empty?

        type, value = parsed
        case type
        when :and
          build_and_expression(value)
        when :or
          value.map { |sub| to_match_expression(sub) }.join(" OR ")
        else
          node_to_match(parsed)
        end
      end

      private

      def build_and_expression(nodes)
        non_excludes = nodes.reject { |n| n.first == :exclude }
        excludes = nodes.select { |n| n.first == :exclude }

        parts = non_excludes.map { |n| node_to_match(n) }
        result = (parts.size == 1) ? parts.first : "(#{parts.join(" AND ")})"

        excludes.each do |node|
          _, value = node
          result = "#{result} NOT \"#{escape(value)}\""
        end

        result
      end

      def node_to_match(node)
        type, value = node
        case type
        when :term
          '"' + escape(value) + '"*'
        when :phrase
          '"' + escape(value) + '"'
        when :exclude
          nil
        end
      end

      def validate!(query)
        if query.bytesize > MAX_QUERY_LENGTH
          raise InvalidQueryError, "Query too long (max #{MAX_QUERY_LENGTH} chars)"
        end
        raise InvalidQueryError, "Query contains invalid characters" if query.include?("\x00")
      end

      def tokenize(query)
        tokens = []
        scanner = StringScanner.new(query)

        until scanner.eos?
          scanner.skip(/\s+/)
          break if scanner.eos?

          if scanner.scan('"')
            phrase = scanner.scan_until(/"/)
            if phrase
              tokens << Token.new(:phrase, phrase.chomp('"'))
            else
              tokens << Token.new(:term, scanner.rest)
              scanner.terminate
            end
          elsif scanner.scan("-")
            scanner.skip(/\s+/)
            tokens << Token.new(:exclude, scanner.scan(/\S+/))
          elsif scanner.scan(/OR|or/i)
            tokens << Token.new(:or, nil)
          else
            tokens << Token.new(:term, scanner.scan(/\S+/))
          end
        end

        tokens
      end

      def split_or(tokens)
        clauses = []
        current = []

        tokens.each do |token|
          if token.type == :or
            clauses << current unless current.empty?
            current = []
          else
            current << token
          end
        end
        clauses << current unless current.empty?
        clauses
      end

      def parse_and_clause(tokens)
        nodes = tokens.map do |token|
          case token.type
          when :term then [:term, token.value]
          when :phrase then [:phrase, token.value]
          when :exclude then [:exclude, token.value]
          end
        end

        (nodes.size == 1) ? nodes.first : [:and, nodes]
      end

      def escape(value)
        value.to_s.gsub('"', '""')
      end
    end
  end
end
