# frozen_string_literal: true

module FullSearch
  class Dsl
    attr_reader :fields, :exact_matches, :filters, :model_class, :highlight_config, :rank_bys, :index_if_sql

    Field = Data.define(:name, :weight, :source, :reindex_on, :async, :async_source, :as, :version)
    ExactMatch = Data.define(:name, :source, :sql, :version)
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

    def field(name, weight: 1, source: nil, reindex_on: nil,
              async: FullSearch.config.default_async_reindex,
              async_source: FullSearch.config.default_async_source_reindex,
              as: nil, version: nil)
      unless valid_name?(name)
        raise InvalidFieldError, "#{model_class.name}: invalid field name #{name.inspect}"
      end
      if as && !valid_name?(as)
        raise InvalidFieldError, "#{model_class.name}: invalid field alias (as): #{as.inspect}"
      end
      str = name.to_s
      raise InvalidFieldError, "#{model_class.name}: duplicate field name #{name.inspect}" if fields.any? { |f| f.name == str }
      raise InvalidFieldError, "#{model_class.name}: field name #{name.inspect} conflicts with existing filter" if filters.any? { |f| f.name == str }
      @fields << Field.new(
        name: str, weight: weight.to_i, source: source,
        reindex_on: reindex_on&.to_s, async: async,
        async_source: async_source, as: as&.to_s, version: version
      )
    end

    def exact_match(name, source: -> { public_send(name) }, sql: nil, version: nil)
      unless valid_name?(name)
        raise InvalidFieldError, "#{model_class.name}: invalid exact_match name #{name.inspect}"
      end
      str = name.to_s
      raise InvalidFieldError, "#{model_class.name}: duplicate exact_match name #{name.inspect}" if exact_matches.any? { |e| e.name == str }
      @exact_matches << ExactMatch.new(name: str, source: source, sql: sql&.to_s, version: version)
    end

    def rank_by(column, direction = :desc)
      unless valid_name?(column)
        raise InvalidFieldError, "#{model_class.name}: invalid rank_by column #{column.inspect}"
      end
      dir = direction.to_s.downcase
      unless %w[asc desc].include?(dir)
        raise InvalidFieldError, "#{model_class.name}: invalid rank_by direction #{direction.inspect}. Use :asc or :desc."
      end
      str = column.to_s
      raise InvalidFieldError, "#{model_class.name}: duplicate rank_by column #{column.inspect}" if rank_bys.any? { |r| r.column == str }
      @rank_bys << RankBy.new(column: str, direction: dir.to_sym)
    end

    def filter(name, required: false)
      unless valid_name?(name)
        raise InvalidFieldError, "#{model_class.name}: invalid filter name #{name.inspect}"
      end
      str = name.to_s
      raise InvalidFieldError, "#{model_class.name}: duplicate filter name #{name.inspect}" if filters.any? { |f| f.name == str }
      raise InvalidFieldError, "#{model_class.name}: filter name #{name.inspect} conflicts with existing field" if fields.any? { |f| f.name == str }
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
      @highlight_config = {open_tag: open_tag, close_tag: close_tag}
    end

    def index_if(sql: nil)
      @index_if_sql = sql&.to_s
    end

    def conditional_index?
      @index_if_sql.present?
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
        index_if_sql,
        fields.map { |f| [f.name, f.weight, f.source.nil? ? "column" : "proc:#{f.version}", f.reindex_on, f.async, f.async_source, f.as] },
        exact_matches.map { |e| [e.name, "proc:#{e.version}", e.sql] },
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
