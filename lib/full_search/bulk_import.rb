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
      rescue => e
        # Triggers are still dropped at this point; the FTS index will rot on
        # every subsequent write. Retry once, then raise loudly so the caller
        # knows the index is compromised instead of failing silent.
        retry_count = (Thread.current[:_fs_bulk_import_retry] ||= 0)
        if retry_count < 1
          Thread.current[:_fs_bulk_import_retry] = retry_count + 1
          retry
        end
        raise FullSearch::TriggerRestoreError,
          "Failed to restore FTS triggers for #{model.table_name} after bulk import: #{e.message}"
      ensure
        Thread.current[:_fs_bulk_import_retry] = nil
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
