# frozen_string_literal: true

require "active_job"

module FullSearch
  class ReindexJob < ActiveJob::Base
    def perform(model_name, record_id, field_name)
      model = model_name.constantize
      record = model.find_by(id: record_id)
      return unless record

      FullSearch::Callbacks.reindex_field!(record, field_name)
    end
  end
end
