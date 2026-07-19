# frozen_string_literal: true

module FullSearch
  module Quoting
    private

    def q(value) = connection.quote(value)
    def qt(name) = connection.quote_table_name(name)
    def qc(name) = connection.quote_column_name(name)
  end
end
