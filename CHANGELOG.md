# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.3.0 — Security and operational hardening

### Fixed

- All SQL identifiers (table names, column names, trigger names) are now quoted using
  `quote_table_name`/`quote_column_name` to prevent SQL injection.
- Record IDs in callbacks are now quoted/escaped before interpolation.
- Filter keys are whitelisted against DSL declarations; unknown keys raise
  `UnknownFilterError`.
- `rank_by` direction is validated against `:asc`/`:desc` before interpolation.
- Bare `rescue` blocks replaced with specific exception handling (`NoMethodError`,
  `NameError`, `LoadError`).
- `UnsupportedDatabaseError` is now raised when a non-SQLite adapter is used.
- `auto_rebuild_schema` now defaults to `false`; generator sets it to `Rails.env.local?`.

### Added

- `UnknownFilterError` for undeclared filter keys.
- `check_stale_config!` — raises `ConfigChangedError` when index config is out of date.
- SQL injection safety, adapter, and stale-config test coverage.

## Unreleased

### Added

- GitHub Actions CI matrix testing Ruby 3.1, 3.2, 3.3 against Rails 8.0 and 8.1.
- StandardRB linting via `rake standard` and `bin/lint`.
- Gemspec signing metadata (`cert_chain`, `signing_key`) for future signed releases.
- `required_rubygems_version` to gemspec.
- README requirements section and CI badge.
- `CHANGELOG.md`.

### Changed

- Lowered `required_ruby_version` from `3.2.0` to `3.1.0`.
- `Gemfile` now reads the Rails version from `RAILS_VERSION` env var for CI matrix support.

### Removed

- Committed `.gem` files from `pkg/`.
- Committed `.ruby-lsp/` directory.
- Committed `Gemfile.lock` from version control.

## 0.2.0

- Initial public release with FTS5-backed full-text search, DSL, filters, highlighting, typo tolerance, and background jobs.
