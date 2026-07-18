# full_search

SQLite FTS5 full-text search for Rails/ActiveRecord.

## Usage

```ruby
class Customer < ApplicationRecord
  full_search do
    field :first_name, weight: 5
    field :last_name,  weight: 5
    filter :account_id, required: true
  end
end
```

See `docs/superpowers/specs/2026-07-18-full_search-gem-design.md` in Wenmar Pro for the full design.
