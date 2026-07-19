# frozen_string_literal: true

module FullSearch
  module Typo
    MIN_SQLITE_VERSION = [3, 34].freeze

    class << self
      def supported?(model = nil)
        conn = model&.connection || ActiveRecord::Base.connection
        major, minor = sqlite_version_parts(conn)
        major > MIN_SQLITE_VERSION.first || (major == MIN_SQLITE_VERSION.first && minor >= MIN_SQLITE_VERSION.last)
      end

      def warn_unsupported!(model = nil)
        version = sqlite_version(model&.connection || ActiveRecord::Base.connection)
        warn "[full_search] SQLite #{version} does not support the trigram tokenizer. typo_tolerance requires SQLite >= 3.34."
      end

      private

      def sqlite_version_parts(conn)
        sqlite_version(conn).split(".").first(2).map(&:to_i)
      end

      def sqlite_version(conn)
        conn.execute("SELECT sqlite_version() AS v").first["v"]
      end
    end
  end
end
