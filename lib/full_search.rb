# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/concern"

require "full_search/index_cache"
require "full_search/version"
require "full_search/config"
require "full_search/distance"
require "full_search/quoting"
require "full_search/errors"
require "full_search/tokenizer"
require "full_search/dsl"
require "full_search/model"
require "full_search/index"
require "full_search/exact_match"
require "full_search/query_parser"
require "full_search/highlighter"
require "full_search/typo"
require "full_search/search"
require "full_search/soft_delete"
require "full_search/callbacks"
require "full_search/reindex_job"
require "full_search/optimize_job"
require "full_search/bulk_import"
require "full_search/backfill_job"
require "full_search/test_helpers"
require "full_search/multi_search"
require "full_search/schema_dumper_patch"

ActiveSupport.on_load(:active_record) do
  include FullSearch::Model
end

module FullSearch
  class << self
    def models
      @models ||= Set.new
    end

    def register_model(model)
      models << model
    end

    def deregister_model(model)
      models.delete(model)
    end

    def optimize!
      models.each { |model| Index.optimize!(model) }
    end

    def setup!
      models.each do |model|
        Index.ensure_table!(model)
        Callbacks.install!(model)
      end
    end

    def bulk_import(model, &block)
      BulkImport.bulk_import(model, &block)
    end

    def bulk_importing?(model)
      BulkImport.bulk_importing?(model)
    end
  end
end

require "full_search/railtie" if defined?(Rails::Railtie)
