# Operational / packaging improvements design

> **Status:** Approved for implementation  
> **Scope:** No feature or test-logic changes. Only packaging, CI, linting, and repository hygiene.

## Goal

Bring `full_search` gem packaging and repository hygiene up to the level expected of a published Ruby gem:
- Make the Ruby/Rails version requirements realistic for current adopters.
- Add continuous integration.
- Remove accidentally committed files from git.
- Add linting, signing metadata, and a changelog.

## Decisions

1. **Ruby minimum:** `>= 3.1.0`.
2. **Rails minimum:** Keep gemspec at `>= 8.0`, but CI must test against **both** Rails 8.0 and 8.1.
3. **Linter:** StandardRB (`standard` gem).
4. **Signing:** Add gemspec metadata pointing at expected cert paths. Do not generate or commit cert files now.
5. **Changelog:** Hand-maintained `CHANGELOG.md` starting with current work.
6. **CI strategy:** Environment-variable based matrix (`RAILS_VERSION`) rather than Appraisal, because only two Rails versions need testing.

## Files to modify

| File | Change |
|------|--------|
| `full_search.gemspec` | `required_ruby_version`, `required_rubygems_version`, `cert_chain`, `signing_key`, `metadata` (optional), add `standard` dev dependency. |
| `Gemfile` | Read Rails version from `ENV["RAILS_VERSION"]` with a `~> 8.1` default for local development. |
| `README.md` | Update "Ruby >= 4.0" statement; mention supported Ruby/Rails versions and CI status. |
| `.gitignore` | Add `.ruby-lsp/`, ensure `pkg/`, `Gemfile.lock` are ignored. |
| `Rakefile` | Add `require "standard/rake"` so `rake standard` and `rake standard:fix` work. |

## Files to create

| File | Purpose |
|------|---------|
| `.github/workflows/ci.yml` | Run tests on Ruby 3.1, 3.2, 3.3 × Rails 8.0, 8.1 and run StandardRB. |
| `CHANGELOG.md` | Human-maintained changelog with `Unreleased` and `0.2.0` sections. |
| `bin/lint` (optional) | Convenience script to run `bundle exec rake standard`. |

## Files to delete from git (and disk)

- `pkg/full_search-0.1.0.gem`
- `pkg/full_search-0.1.1.gem`
- `pkg/full_search-0.1.2.gem`
- `pkg/full_search-0.1.3.gem`
- `pkg/full_search-0.2.0.gem`
- Entire `.ruby-lsp/` directory.
- `Gemfile.lock`.

## CI matrix

```yaml
strategy:
  matrix:
    ruby: ["3.1", "3.2", "3.3"]
    rails: ["8.0", "8.1"]
    include:
      - ruby: "3.4"  # if available and stable; otherwise omit
        rails: "8.1"
```

Use `RAILS_VERSION` env var in each job, and have `Gemfile` interpret it:

```ruby
rails_version = ENV.fetch("RAILS_VERSION", "8.1")
gem "activerecord", "~> #{rails_version}"
gem "activejob", "~> #{rails_version}"
gem "railties", "~> #{rails_version}"
```

CI steps:
1. Checkout code.
2. Set up Ruby.
3. `bundle install`.
4. `bundle exec rake test`.
5. `bundle exec rake standard` (run once per Ruby version, or in a separate lint job).

## Linting

- Add `standard` (~> 1.40) as a development dependency in the gemspec.
- Load StandardRB rake tasks in `Rakefile`.
- Add one initial mechanical commit that runs `bundle exec rake standard:fix` across the repo.
- From that point on, CI enforces StandardRB.

## Gem signing metadata

In the gemspec:

```ruby
spec.required_rubygems_version = ">= 2.0"
spec.cert_chain = ["cert/full_search.pem"]
spec.signing_key = "cert/priv_key.pem" if File.exist?("cert/priv_key.pem")
```

This points at paths without forcing a build-time signing requirement.

## Changelog format

Use [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format, starting with `Unreleased` and the existing `0.2.0` release.

## Out of scope

- Dropping Rails requirement below 8.0.
- Adding Appraisal.
- Automating signed releases via GitHub Actions.
- Adding RuboCop (using StandardRB instead).

## Success criteria

- `bundle exec rake test` passes locally with Rails 8.1.
- CI passes for Ruby 3.1, 3.2, 3.3 against Rails 8.0 and 8.1.
- `bundle exec rake standard` passes.
- `pkg/`, `.ruby-lsp/`, and `Gemfile.lock` are no longer tracked.
- README no longer claims Ruby 4.0+ is required.
