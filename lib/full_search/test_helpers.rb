# frozen_string_literal: true

module FullSearch
  module TestHelpers
    class << self
      def setup_for_tests!
        configure do |config|
          config.lock_rebuilds = false
          config.auto_rebuild_on_stale_query = true
          config.stale_query_behavior = :raise
          config.auto_rebuild_missing_tables = true
        end

        inline_active_job_if_configured
      end

      def configure
        yield FullSearch.config
      end

      private

      def inline_active_job_if_configured
        return unless defined?(ActiveJob::Base)

        ActiveJob::Base.queue_adapter = :inline
      end
    end

    def rebuild_full_search_index(model)
      model = resolve_full_search_model(model)
      FullSearch::Index.drop!(model)
      FullSearch::Index.rebuild!(model)
    end

    def reindex_full_search(model)
      model = resolve_full_search_model(model)
      FullSearch::Index.reindex_source_fields!(model)
    end

    def reset_full_search!(*models)
      models = FullSearch.models.to_a if models.empty?
      models.each { |model| rebuild_full_search_index(model) }
    end

    def truncate_full_search!(*models)
      models = FullSearch.models.to_a if models.empty?
      models.each { |model| FullSearch::Index.truncate!(model) }
    end

    def ensure_full_search_tables
      FullSearch.models.each do |model|
        FullSearch::Index.ensure_table!(model)
      end
    end

    def once_full_search_rebuilt(*models, &block)
      FullSearch::OnceRebuilt.per_test_case(*models, &block)
    end

    def with_full_search_rebuild(model)
      model = resolve_full_search_model(model)
      rebuild_full_search_index(model)
      yield
    ensure
      FullSearch::Index.drop!(model)
    end

    def with_full_search_async_jobs_inline
      original_adapter = ActiveJob::Base.queue_adapter if defined?(ActiveJob::Base)
      ActiveJob::Base.queue_adapter = :inline if defined?(ActiveJob::Base)
      yield
    ensure
      ActiveJob::Base.queue_adapter = original_adapter if defined?(ActiveJob::Base)
    end

    def with_full_search_models_registered(*models)
      previous_registry = FullSearch.models.dup
      models.each { |model| FullSearch.register_model(model) }
      yield
    ensure
      FullSearch.models.replace(previous_registry)
    end

    private

    def resolve_full_search_model(model)
      return model if model.is_a?(Class)

      model.to_s.camelize.constantize
    end
  end
end
