# frozen_string_literal: true

module FullSearch
  class Error < StandardError; end
  class MissingRequiredFilterError < Error; end
  class UnknownFilterError < Error; end
  class ConfigChangedError < Error; end
  class InvalidFieldError < Error; end
  class NotConfiguredError < Error; end
  class UnsupportedDatabaseError < Error; end
  class MissingTableError < Error; end
  class InvalidQueryError < Error; end
end
