# frozen_string_literal: true

module FullSearch
  module Typo
    MIN_SQLITE_VERSION = [3, 34].freeze

    class << self
      def supported?
        major, minor = sqlite_version_parts
        major > MIN_SQLITE_VERSION.first || (major == MIN_SQLITE_VERSION.first && minor >= MIN_SQLITE_VERSION.last)
      end

      def warn_unsupported!
        warn "[full_search] SQLite #{sqlite_version} does not support the trigram tokenizer. typo_tolerance requires SQLite >= 3.34."
      end

      private

      def sqlite_version_parts
        sqlite_version.split(".").first(2).map(&:to_i)
      end

      def sqlite_version
        ActiveRecord::Base.connection.execute("SELECT sqlite_version() AS v").first["v"]
      end
    end
  end
end
