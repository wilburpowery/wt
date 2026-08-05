# wt

Instant Laravel worktrees with [Laravel Herd](https://herd.laravel.com). One command gives you a fully working parallel copy of your app: its own branch, its own cloned database, its own Herd site with TLS, its own pinned PHP version, dependencies installed, migrations run.

```bash
wt new sup-1234
# a few minutes later: https://sup-1234.test is a fully working app

wt rm sup-1234
# site unlinked, databases dropped, worktree removed
```

Useful for reviewing PRs with a running app, testing risky migrations against a disposable copy of your dev data, and running parallel AI coding agent sessions without them fighting over one checkout's HEAD.

## Install

```bash
brew install wilburpowery/tap/wt
```

Or drop the `wt` script anywhere on your PATH.

## Requirements

- macOS (APFS is used for copy-on-write dependency cloning)
- [Laravel Herd](https://herd.laravel.com) serving your app (free tier is fine)
- A local MySQL on `127.0.0.1:3306` reachable as `root` with no password (e.g. [DBngin](https://dbngin.com)) — configurable via `WT_MYSQL`

## What `wt new <slug>` does

1. **Resolves the branch** — existing local branch, else fetch + track `origin/<branch>`, else a new branch off the repo's default branch (read from `origin/HEAD`, so `main` and `master` repos both work). Branch name defaults to `<prefix><slug>`.
2. **Copies your git-ignored config** (`.env`, certs, keys) from the main checkout — worktrees only share tracked files.
3. **Rewrites the env for isolation** — `APP_URL`, `SESSION_DOMAIN`, and `DB_DATABASE` point at slug-specific values.
4. **Links the site in Herd** (`herd link <slug> --secure`, with `--isolate` when a PHP version is configured) — *before* installing anything, because unlinked directories float to the newest installed PHP and break `composer install` on version-pinned apps.
5. **Clones the database** — `mysqldump --single-transaction` into `<db>_<slug>`, so migrations in the worktree can't touch your main data.
6. **Clones dependencies via APFS copy-on-write** — every `node_modules` and composer `vendor` in the main checkout is cloned with `cp -c` (instant, near-zero disk), then the real installers run as a fast reconcile against the worktree branch's lockfiles.
7. **Builds frontend assets** when the app has a `vite.config.*` and a `build` script (Laravel 500s without `public/build/manifest.json`, which is git-ignored).
8. **Runs migrations.**

`wt rm <slug>` reverses all of it (the branch is deliberately kept). `wt list` shows every worktree plus any orphaned worktree databases left in MySQL.

## Configuration

Zero config works for a plain Laravel app served by Herd: app at the repo root, database derived from `.env`'s `DB_DATABASE`, package manager detected by lockfile.

For everything else there are two bash config files, sourced in order: `~/.wtrc` (global), then `<repo>/.wtrc` (per repo — keep it out of git via `.git/info/exclude`).

### Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `WT_APP_DIR` | `.` | Where the Laravel app lives (e.g. `apps/backend` in a monorepo) |
| `WT_PHP` | none | PHP version for `herd link --isolate` |
| `WT_BRANCH_PREFIX` | `git config wt.branchPrefix`, else empty | New branches become `<prefix><slug>` |
| `WT_DB_SOURCE` | derived from `.env` | Database to clone |
| `WT_TEST_DB_SOURCE` | none | Optional second (test) database to clone; also writes `.env.testing.local` |
| `WT_COPY` | auto (`.env` files) | Repo-relative paths to copy into new worktrees |
| `WT_DEFAULT_BRANCH` | from `origin/HEAD` | Base for new branches |
| `WT_MYSQL` | `mysql -h127.0.0.1 -P3306 -uroot` | MySQL CLI connection |

### Hooks

Define bash functions in a `.wtrc` to replace any lifecycle step. Hooks run inside `wt`'s shell, so helpers like `free_port`, `wt_has_flag`, `wt_clone_deps`, and `wt_composer_bin` are available.

| Hook | Default behavior |
| --- | --- |
| `wt_host <slug>` | echoes `<slug>.test` |
| `wt_env_extra <wt> <slug> <host> <db>` | no-op (extra env rewrites) |
| `wt_install <wt>` | CoW-clone deps, then npm/pnpm/yarn + composer reconcile |
| `wt_post_create <wt>` | build Vite assets if present, `php artisan migrate` |
| `wt_pre_remove <wt>` | no-op |
| `wt_list_extra <wt>` | no-op (extra `wt list` lines) |

### Repo-defined subcommands and flags

An unknown subcommand `wt foo` dispatches to `wt_cmd_foo` if the `.wtrc` defines it. Unknown `--flags` passed to `wt new` are collected for hooks to inspect via `wt_has_flag`. Example: a monorepo can define a `--with-dashboard` flag that mints a TLS cert and a dedicated frontend port, plus a `wt dashboard <slug>` subcommand that boots it — without the core script knowing dashboards exist.

```bash
# <repo>/.wtrc for a monorepo
WT_APP_DIR="apps/backend"
WT_PHP="8.4"
WT_TEST_DB_SOURCE="myapp_test"
WT_COPY=(".env" ".cert" "apps/backend/.env")

wt_post_create() {
  local wt="$1"
  (cd "$wt/apps/backend" && pnpm exec turbo run build --filter="myapp^..." && pnpm dev:build)
  (cd "$wt/apps/backend" && herd php artisan migrate --no-interaction)
}
```

## Gotchas the tool encodes

- **Link before composer.** Herd resolves PHP per site; unlinked dirs float to the newest PHP and locked dependencies explode.
- **Never use Herd's `composer`/bare `php` shims** for this — they ignore site isolation. `wt` runs composer's phar under `herd php`, which resolves isolation from the working directory.
- **Git-ignored runtime artifacts don't exist in fresh worktrees** — built assets, package `dist/` folders. Anything your app needs at runtime that isn't tracked needs a build step (the defaults handle the common Laravel + Vite case).
- **`package.json` without a `name` field** makes npm rewrite `package-lock.json` in every worktree (it infers the name from the directory). Add a `name`.

## License

MIT

## Releasing (maintainer)

```bash
./release.sh 0.1.1
```

Bumps `WT_VERSION`, commits, tags `v<version>`, pushes, then updates `url` + `sha256` in the tap formula (`../homebrew-tap/Formula/wt.rb`, override with `WT_TAP_DIR`) and pushes that too. Users get the new version with `brew update && brew upgrade wt`.
