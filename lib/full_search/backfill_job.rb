# frozen_string_literal: true

require "active_job"

module FullSearch
  class BackfillJob < ActiveJob::Base
    queue_as :low

    def perform(model_name)
      model = model_name.to_s.constantize
      FullSearch::Index.rebuild!(model)
    end
  end
end
