# frozen_string_literal: true

require "active_job"

module FullSearch
  class ReindexJob < ActiveJob::Base
    queue_as :low

    def perform(model_name, record_id, field_name = nil)
      model = model_name.is_a?(Class) ? model_name : model_name.to_s.constantize
      record = model.find_by(id: record_id)
      return unless record

      if field_name
        FullSearch::Callbacks.reindex_field!(record, field_name)
      else
        FullSearch::Callbacks.reindex_record!(record)
      end
    end
  end
end
