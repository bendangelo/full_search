# frozen_string_literal: true

module FullSearch
  module Distance
    def self.damerau_levenshtein(a, b)
      a_len = a.length
      b_len = b.length
      return a_len if b_len == 0
      return b_len if a_len == 0

      d = Array.new(a_len + 1) { Array.new(b_len + 1, 0) }
      (0..a_len).each { |i| d[i][0] = i }
      (0..b_len).each { |j| d[0][j] = j }

      (1..a_len).each do |i|
        (1..b_len).each do |j|
          cost = (a[i - 1] == b[j - 1]) ? 0 : 1
          d[i][j] = [
            d[i - 1][j] + 1,
            d[i][j - 1] + 1,
            d[i - 1][j - 1] + cost
          ].min

          if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]
            d[i][j] = [d[i][j], d[i - 2][j - 2] + 1].min
          end
        end
      end

      d[a_len][b_len]
    end
  end
end
