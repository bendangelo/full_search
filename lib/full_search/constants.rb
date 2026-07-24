# frozen_string_literal: true

module FullSearch
  module Constants
    MIN_TERM_LENGTH = 3
    TWO_TYPO_MIN_LENGTH = 9
    DEFAULT_MIN_LIKE_PREFIX_LENGTH = 3
    REBUILDING_HASH = "__rebuilding__"
    DEFAULT_TOKENIZER = "unicode61"
    MAX_EXACT_MATCH_BOOST_IDS = 100
  end
end
