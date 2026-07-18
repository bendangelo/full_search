# frozen_string_literal: true

module FullSearch
  class Dsl
    attr_reader :fields, :exact_matches, :filters, :model_class, :tokenize

    Field = Data.define(:name, :weight, :source, :reindex_on, :async)
    ExactMatch = Data.define(:name, :source)
    Filter = Data.define(:name, :required)

    def initialize(model_class)
      @model_class = model_class
      @fields = []
      @exact_matches = []
      @filters = []
      @tokenize = FullSearch.config.default_tokenizer
      @soft_delete_column = nil
    end

    def field(name, weight: 1, source: nil, reindex_on: nil, async: FullSearch.config.default_async_reindex)
      unless valid_name?(name)
        raise InvalidFieldError, "Invalid field name: #{name.inspect}"
      end
      @fields << Field.new(name: name.to_s, weight: weight.to_i, source: source, reindex_on: reindex_on&.to_s, async: async)
    end

    def exact_match(name, source: -> { public_send(name) })
      unless valid_name?(name)
        raise InvalidFieldError, "Invalid exact_match name: #{name.inspect}"
      end
      @exact_matches << ExactMatch.new(name: name.to_s, source: source)
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

    def tokenize(value)
      @tokenize = Tokenizer.validate!(value)
    end

    def config_hash
      require "digest"
      Digest::SHA256.hexdigest([
        model_class.table_name,
        tokenize,
        soft_delete_column,
        fields.map { |f| [f.name, f.weight, f.source.nil? ? "column" : "source", f.reindex_on, f.async] },
        exact_matches.map { |e| [e.name] },
        filters.map { |f| [f.name, f.required] }
      ].inspect)
    end

    private

    def valid_name?(name)
      name.to_s.match?(/\A[a-zA-Z_]\w*\z/)
    end
  end
end
