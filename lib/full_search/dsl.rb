# frozen_string_literal: true

module FullSearch
  class Dsl
    attr_reader :fields, :exact_matches, :filters, :model_class, :tokenize, :highlight_config, :rank_bys

    Field = Data.define(:name, :weight, :source, :reindex_on, :async, :as)
    ExactMatch = Data.define(:name, :source)
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

    def field(name, weight: 1, source: nil, reindex_on: nil, async: FullSearch.config.default_async_reindex, as: nil)
      unless valid_name?(name)
        raise InvalidFieldError, "Invalid field name: #{name.inspect}"
      end
      if as && !valid_name?(as)
        raise InvalidFieldError, "Invalid field alias (as): #{as.inspect}"
      end
      @fields << Field.new(name: name.to_s, weight: weight.to_i, source: source, reindex_on: reindex_on&.to_s, async: async, as: as&.to_s)
    end

    def exact_match(name, source: -> { public_send(name) })
      unless valid_name?(name)
        raise InvalidFieldError, "Invalid exact_match name: #{name.inspect}"
      end
      @exact_matches << ExactMatch.new(name: name.to_s, source: source)
    end

    def rank_by(column, direction = :desc)
      unless valid_name?(column)
        raise InvalidFieldError, "Invalid rank_by column: #{column.inspect}"
      end
      @rank_bys << RankBy.new(column: column.to_s, direction: direction.to_sym)
    end

    def filter(name, required: false)
      unless valid_name?(name)
        raise InvalidFieldError, "Invalid filter name: #{name.inspect}"
      end
      @filters << Filter.new(name: name.to_s, required: required)
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
        fields.map { |f| [f.name, f.weight, f.source.nil? ? "column" : f.source.source_location&.join(":"), f.reindex_on, f.async, f.as] },
        exact_matches.map { |e| [e.name, e.source&.source_location&.join(":")] },
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
