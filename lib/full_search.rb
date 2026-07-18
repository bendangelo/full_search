# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/concern"

require "full_search/version"
require "full_search/config"
require "full_search/errors"
require "full_search/tokenizer"
require "full_search/dsl"
require "full_search/model"
require "full_search/index"
require "full_search/exact_match"
require "full_search/search"

ActiveSupport.on_load(:active_record) do
  include FullSearch::Model
end

module FullSearch
  class << self
    def models
      @models ||= []
    end
  end
end
