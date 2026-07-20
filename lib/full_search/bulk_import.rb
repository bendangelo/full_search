# frozen_string_literal: true

module FullSearch
  module BulkImport
    class << self
      def bulk_import(model)
        start_bulk_import(model)
        yield
      ensure
        end_bulk_import(model)
      end

      def start_bulk_import(model)
        models_in_bulk_import << model
        FullSearch::Index.drop_triggers!(model)
      end

      def end_bulk_import(model)
        models_in_bulk_import.delete(model)
        FullSearch::Index.create_triggers!(model)
        FullSearch::BackfillJob.perform_later(model.name)
      end

      def bulk_importing?(model)
        models_in_bulk_import.include?(model)
      end

      private

      def models_in_bulk_import
        Thread.current[:full_search_bulk_import_models] ||= Set.new
      end
    end
  end
end
