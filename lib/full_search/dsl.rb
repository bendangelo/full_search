# frozen_string_literal: true

module FullSearch
  class Dsl
    attr_reader :fields, :exact_matches, :filters, :model_class, :tokenize, :highlight_config, :rank_bys

    Field = Data.define(:name, :weight, :source, :reindex_on, :async, :as, :version)
    ExactMatch = Data.define(:name, :source, :version)
    Filter = Data.define(:name, :required)
    RankBy = Data.define(:column, :direction)

    def initialize(model_class)
      @model_class = model_class
      @fields = []
      @exact_matches = []
      @filters = []
      @rank_bys = []
      @tokenize = FullSearch.config.default_tokenizer
      @soft_delete_column = nil
    end

    def field(name, weight: 1, source: nil, reindex_on: nil, async: FullSearch.config.default_async_reindex, as: nil, version: nil)
      unless valid_name?(name)
        raise InvalidFieldError, "Invalid field name: #{name.inspect}"
      end
      if as && !valid_name?(as)
        raise InvalidFieldError, "Invalid field alias (as): #{as.inspect}"
      end
      str = name.to_s
      raise InvalidFieldError, "Duplicate field name: #{name.inspect}" if fields.any? { |f| f.name == str }
      raise InvalidFieldError, "Field name conflicts with filter: #{name.inspect}" if filters.any? { |f| f.name == str }
      @fields << Field.new(name: str, weight: weight.to_i, source: source, reindex_on: reindex_on&.to_s, async: async, as: as&.to_s, version: version)
    end

    def exact_match(name, source: -> { public_send(name) }, version: nil)
      unless valid_name?(name)
        raise InvalidFieldError, "Invalid exact_match name: #{name.inspect}"
      end
      str = name.to_s
      raise InvalidFieldError, "Duplicate exact_match name: #{name.inspect}" if exact_matches.any? { |e| e.name == str }
      @exact_matches << ExactMatch.new(name: str, source: source, version: version)
    end

    def rank_by(column, direction = :desc)
      unless valid_name?(column)
        raise InvalidFieldError, "Invalid rank_by column: #{column.inspect}"
      end
      str = column.to_s
      raise InvalidFieldError, "Duplicate rank_by column: #{column.inspect}" if rank_bys.any? { |r| r.column == str }
      @rank_bys << RankBy.new(column: str, direction: direction.to_sym)
    end

    def filter(name, required: false)
      unless valid_name?(name)
        raise InvalidFieldError, "Invalid filter name: #{name.inspect}"
      end
      str = name.to_s
      raise InvalidFieldError, "Duplicate filter name: #{name.inspect}" if filters.any? { |f| f.name == str }
      raise InvalidFieldError, "Filter name conflicts with field: #{name.inspect}" if fields.any? { |f| f.name == str }
      @filters << Filter.new(name: str, required: required)
    end

    def soft_delete_column(name = :_no_arg_)
      if name == :_no_arg_
        @soft_delete_column
      else
        @soft_delete_column = name.to_s
      end
    end

    def tokenize(value = :_no_arg_)
      if value == :_no_arg_
        @tokenize
      else
        @tokenize = Tokenizer.validate!(value)
      end
    end

    def highlight(open_tag: "<mark>", close_tag: "</mark>")
      @highlight_config = { open_tag: open_tag, close_tag: close_tag }
    end

    def typo_tolerance(enabled = true, min_term_length: nil)
      @typo_tolerance = enabled
      @typo_tolerance_min_term_length = min_term_length || 3
    end

    def typo_tolerance?
      !!@typo_tolerance
    end

    def typo_tolerance_min_term_length
      @typo_tolerance_min_term_length || 3
    end

    def config_hash
      require "digest"
      Digest::SHA256.hexdigest([
        model_class.table_name,
        tokenize,
        soft_delete_column,
        typo_tolerance?,
        typo_tolerance_min_term_length,
        fields.map { |f| [f.name, f.weight, f.source.nil? ? "column" : "proc:#{f.version}", f.reindex_on, f.async, f.as] },
        exact_matches.map { |e| [e.name, "proc:#{e.version}"] },
        filters.map { |f| [f.name, f.required] },
        rank_bys.map { |r| [r.column, r.direction] }
      ].inspect)
    end

    private

    def valid_name?(name)
      name.to_s.match?(/\A[a-zA-Z_]\w*\z/)
    end

  end
end
