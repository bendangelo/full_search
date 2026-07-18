# frozen_string_literal: true

module FullSearch
  module Tokenizer
    VALID = %w[unicode61 porter trigram].freeze

    def self.validate!(value)
      value = value.to_s
      unless VALID.include?(value)
        raise InvalidFieldError, "Unsupported tokenizer: #{value.inspect}. Use one of #{VALID.inspect}"
      end
      value
    end
  end
end
