# frozen_string_literal: true

module FullSearch
  module Instrumentation
    def self.instrument(name, payload = {}, &block)
      ActiveSupport::Notifications.instrument("full_search.#{name}", payload, &block)
    end
  end
end
