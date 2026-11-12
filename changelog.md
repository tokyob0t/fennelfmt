# History of user-visible changes

## 0.6.0 / 2026-11-12

* Rename the project to `fennelfmt`. The binary, Lua module, and man page are
  now `fennelfmt`; the project config file is `.fennelfmt.fnl` and the
  environment variable is `FENNELFMT_CONFIG`. The legacy `;; fnlfmt: skip`
  comment is still accepted.
* Remove the user-level config file (`~/.config/...`). Configuration is only
  read from `--config`, `FENNELFMT_CONFIG`, or the nearest `.fennelfmt.fnl`
  in the file's directory tree.
* Keep trailing comments on the same line as the form, key, or value they
  follow instead of moving them to their own line. Consecutive trailing
  comments are aligned in one column after formatting, using the widest
  rendered line (including closing delimiters and comments after them).
  Comments that were already on their own line keep their own line, and an
  own-line comment does not add excessive padding. Semicolons inside
  multi-line strings are left alone.

## 0.5.0 / 2026-11-12

* Add `--diff`, which prints a unified diff for files that need formatting
  and exits 1 if any do, without writing to disk.
* Add `--stdin` as an explicit alias for `-` and `--quiet` to suppress the
  `Not formatted` messages from `--check` and `--check-indent`.
* Report the operating system's actual error when a file cannot be read or
  written instead of always saying `File not found`, and stop calling
  `os.exit` from library code.
* Fix binding, function-argument, and one-per-line alignment when `:indent`
  is not the default 2. These columns now follow the opening delimiter
  instead of the body indentation, so `:indent` only changes body lines.
* Add optional configuration via `.fnlfmt.fnl`, parsed as data and validated
  rather than evaluated. It can be selected with `--config`, ignored with
  `--no-config`, or discovered from the nearest ancestor directory (falling
  back to `$XDG_CONFIG_HOME/fnlfmt/config.fnl`). Defaults still match
  upstream byte for byte.
* Make form classification configurable with `:extra-forms` (extend the
  built-in table), `:forms` (replace it), `:form-patterns` (ordered Lua
  patterns), `:unknown-form-style` (default for unmatched forms), and
  `:infer-macros?` (toggle the `with-`/`def`/`fn/`/`λ/` conventions).
  Available styles are `:call`, `:body`, `:binding`, `:function`, `:match`,
  `:conditional`, `:threading`, `:sequence`, `:block`, and `:maybe-body`.
  The same classification drives `--indent`.
* Add the `:line-length` and `:no-comments` settings, plus `--print-config`
  to show the effective values and which source provided each one.
* Add the `:indent` (body indentation width), `:align-calls?` (align or
  block-indent wrapped call arguments), and `:trailing-newline?` options,
  plus the `:style` presets `:wide` (line length 100) and `:block`
  (block-indented calls). Explicit keys override a preset.
* Fail with a file-and-line diagnostic on unknown keys, bad types, parse
  errors, and unsupported config versions.
* Treat forms whose name starts with `fn/` or `λ/` as function definitions,
  so macros like `fn/a` get their argument list on the first line and their
  body on separate lines. This matches how `with-` and `def` forms were
  already handled.
* `--check` and `--check-indent` now exit with status 1 when a file needs
  formatting; previously they always exited 0.
* `--indent` and `--fix-indent` no longer drop the final line of a file that
  lacks a trailing newline.
* `--indent` no longer prints an extra trailing newline.
* Silence the Fennel plugin version warning and build against the vendored
  Fennel instead of any system-wide install.
* Document `--indent`, `--fix-indent`, `--check-indent`, `--version`, and
  `--help` in `--help` and the man page.
* Install `indentation.lua` alongside `fnlfmt.lua`.
* Add `make check` (tests, self-host check, lint) and GitHub Actions CI;
  `make selfhost` now also covers `test.fnl`.

## 0.4.0 / 2026-09-27

* Add support for `--indent`, `--check-indent`, and `--fix-indent`.
* Preserve notation for strings and numbers.

## 0.3.2 / 2024-09-02

* Add man page.
* Don't write to disk with `--fix` when file is unchanged.
* Fix a bug with binding tables introduced by `->`.
* Fix a bug that would cause extreme indentation.
* Add `--check` command.

## 0.3.1 / 2023-08-03

* Relicense to MIT.
* Fix a bug with comment nodes not having newlines after.
* Support for `case`, `case-try`, and `match-try`.

## 0.3.0 / 2023-01-29

* Treat `with-*` and `def*` forms as macros with a body.
* Improved handling of `&into` and `&until` in iterator bindings.
* Fix a bug where comments in k/v tables could disappear.
* Allow certain forms to preserve one-liner status.
* Fix a bug where table keys weren't always sorted.

## 0.2.3 / 2022-04-26

* Fix a bug around how vargs are handled in Fennel 1.1.0.

## 0.2.2 / 2021-10-01

* Fix a bug with multiple lines of sequential comments in kv tables.

## 0.2.1 / 2021-03-07

* Be more forgiving of ASTs which lack source metadata.

## 0.2.0 / 2021-03-06

* Complete rewrite which uses Fennel's own parser and pretty-printer.
* Good enough to run on all of Fennel's own codebase.

## 0.1.0 / 2020-05-21

* First release of heuristic-based indentation-only formatter.
