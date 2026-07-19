# frozen_string_literal: true

require "active_job"

module FullSearch
  class OptimizeJob < ActiveJob::Base
    queue_as :low

    def perform
      FullSearch.optimize!
    end
  end
end
