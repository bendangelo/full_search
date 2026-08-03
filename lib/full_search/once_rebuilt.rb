# frozen_string_literal: true

module FullSearch
  module OnceRebuilt
    class << self
      def per_test_case(*models)
        models = FullSearch.models.to_a if models.empty?
        unless already_rebuilt?(models)
          rebuild_models!(models)
          mark_rebuilt!(models)
        end

        yield if block_given?
      end

      def clear!
        @rebuilt = Set.new
      end

      private

      def already_rebuilt?(models)
        keys = models.map { |model| cache_key(model) }
        @rebuilt ||= Set.new
        keys.all? { |key| @rebuilt.include?(key) }
      end

      def mark_rebuilt!(models)
        @rebuilt ||= Set.new
        models.each { |model| @rebuilt << cache_key(model) }
      end

      def cache_key(model)
        [
          model.connection_db_config.database,
          model.table_name,
          model.full_search_dsl&.config_hash,
          model.connection_db_config.schema_cache_path
        ].compact.join(":")
      end

      include FullSearch::TestHelpers

      def rebuild_models!(models)
        models.each { |model| rebuild_full_search_index(model) }
      end
    end
  end
end
