# frozen_string_literal: true

require "active_job"

module FullSearch
  class BackfillJob < ActiveJob::Base
    queue_as :low

    def perform(model_name)
      model = model_name.to_s.constantize
      raise UnsupportedDatabaseError, "full_search requires SQLite, but #{model.connection.adapter_name} is configured" unless FullSearch::Index.sqlite?(model)
      FullSearch::Index.rebuild!(model)
    end
  end
end
