# Fennel Format

Format your Fennel!

> **This is a fork.** Upstream is
> [`~technomancy/fnlfmt`](https://git.sr.ht/~technomancy/fnlfmt) on SourceHut.
> This fork is maintained by [@tokyob0t](https://github.com/tokyob0t) at
> <https://github.com/tokyob0t/fnlfmt> and adds opt-in configuration while
> keeping the upstream defaults unchanged. See [Fork notes](#fork-notes).

## Usage

    $ make install PREFIX=$HOME # or sudo make install in /usr/local
    $ ./fnlfmt mycode.fnl # prints formatted code to standard out
    $ ./fnlfmt --fix mycode.fnl # replaces the file with formatted code
    $ ./fnlfmt --check mycode.fnl # checks if the file is formatted
    $ ./fnlfmt --indent mycode.fnl # print with indentation fixed only
    $ curl localhost:8080/my-file.fnl | ./fnlfmt - # pipe to stdin

You can skip reformatting of top-level forms by placing a comment
before them. This does not work for nested forms.

```fennel
(fn this-function [can be formatted ...]
  ...)

;; fnlfmt: skip
(local this-table ["benefits"          :from
                   "different kind of" :FORMATTING
                   "because of"        :reasons])

(fn this-function [will-be]
  (formatted :normally "again, haha"))
```

## Configuration

By default `fnlfmt` behaves exactly like upstream. Optional settings live in a
`.fnlfmt.fnl` file written as Fennel data; it is parsed and validated, never
evaluated:

```fennel
{:version 1
 :style :default
 :line-length 80
 :no-comments false
 :extra-forms {}
 :form-patterns []
 :unknown-form-style :call
 :infer-macros? true}
```

One config file is selected, without merging:

1. `--config PATH` (or `FNLFMT_CONFIG`), if given;
2. otherwise the nearest `.fnlfmt.fnl` found by walking up from the file's
   directory;
3. otherwise `$XDG_CONFIG_HOME/fnlfmt/config.fnl` (or
   `~/.config/fnlfmt/config.fnl`).

`--no-config` ignores every config file. Command line flags such as
`--no-comments` override values from the selected file. Unknown keys,
unsupported versions, and malformed files fail with a message that includes
the file and line, and exit with status 1.

Available settings:

| Key                   | Type    | Default    | Meaning                                  |
|-----------------------|---------|------------|------------------------------------------|
| `:version`            | number  | `1`        | Config format version; must be `1`.      |
| `:style`              | string  | `:default` | Preset name. Only `:default` for now.    |
| `:line-length`        | number  | `80`       | Column after which calls are wrapped.    |
| `:no-comments`        | boolean | `false`    | Strip comments, like `--no-comments`.    |
| `:forms`              | table   | built-in   | Replace the built-in classification table. |
| `:extra-forms`        | table   | `{}`       | Add or override classifications.         |
| `:form-patterns`      | list    | `[]`       | Ordered `[pattern style]` pairs.         |
| `:unknown-form-style` | string  | `:call`    | Style for forms that match nothing else. |
| `:infer-macros?`      | boolean | `true`     | Infer macros from naming conventions.    |

Each entry in `:forms` and `:extra-forms` maps a form name to a style:

| Style        | Behavior                                                        |
|--------------|-----------------------------------------------------------------|
| `:call`      | Normal function call.                                           |
| `:body`      | Body form; arguments after the first are indented as a body.    |
| `:binding`   | Body form whose first argument is a binding table (`let`, `each`). |
| `:function`  | Definition with a name and argument list (`fn`, `fn/a`).        |
| `:match`     | Clause-pairing form (`match`, `case`).                          |
| `:conditional` | Condition/result pairing (`if`).                              |
| `:threading` | Arrow-like form with each step aligned (`->`).                  |
| `:sequence`  | Body form with one argument per line, aligned.                  |
| `:block`     | Body form that always starts on a new line (`do`).              |
| `:maybe-body` | Body or call depending on the original layout.                 |

`:forms` replaces the built-in table entirely; use `:extra-forms` to extend
it. `:form-patterns` entries are checked before the built-in naming
conventions, so a pattern can also override one of them. Setting
`:infer-macros?` to `false` disables only those built-in conventions, not
Fennel's own syntax table.

```fennel
{:extra-forms {:my/with-db :binding
               :defcomponent :function}
 :form-patterns [["^ui/" :body]]
 :unknown-form-style :call}
```

Use `fnlfmt --print-config FILE` to see the effective settings and where each
one came from. The repository's own `.fnlfmt.fnl` spells out every key and
the full default classification table as a reference.

## Development

    $ make test   # run the golden-file and CLI test suite
    $ make check  # test, verify the sources are self-hosted, and lint

The build compiles with the vendored `fennel` (set `FENNEL`/`FENNEL_OPTS` to
override), so it does not depend on a system-wide Fennel install. Run
`make selfhost` after changing formatting behavior to reformat fnlfmt's own
sources. `make check` also needs `fennel-ls` on `PATH`; it falls back to the
Mason install location used by Neovim.

## Description

The goal of `fnlfmt` is *not* to be The One Formatter that all Fennel
programmers use to format their code. We assume that most of the time,
Fennel programmers will use a text editor that already knows how to
indent code correctly, and that `fnlfmt` supplements existing editor
support in cases where for whatever reason the editor functionality
cannot be used. This means that `fnlfmt` should be treated as one
implementation of the standard format rather than being canonical itself.

By design the defaults are not configurable in the sense of changing how
the formatter interprets standard Fennel: formatting choices should be
correct other than bugs or when new features are added to Fennel itself.
The optional `.fnlfmt.fnl` file adjusts presentation settings and lets
third-party macros opt into the same layout rules; see
[Configuration](#configuration). When it comes to where the line breaks are
inserted, it tries its best, but there are certainly cases where a human
could do better. Sometimes when it comes to line breaks it will defer to the
existing code where possible.

## Known issues

* Comments will not be wrapped.
* Single-semicolon full-line comments will not be changed to double-semicolon.
* When using fnlfmt as a library, it may modify the AST argument.
* Function argument lists will be displayed one-per-line if they can't
  all fit on one line. (This is inherited from `fennel.view`.)

Some of the issues are inherent to this approach, or at least cannot
be fixed without major changes:

* Page breaks and other whitespace will not be preserved.
* Macros that take a body argument but aren't built-in will only be indented
  as such if their name starts with `with-`, `def`, `fn/`, or `λ/`. Functions
  which use this naming convention will be indented like `let`.

## Other functionality

The file `indentation.fnl` contains functionality for implementing
heuristic-based indentation which does not use a parser. This can be
useful for text editors where you want to be able to indent even in
cases where the code does not parse because it's incomplete.

The file `macrodebug.fnl` contains a replacement for Fennel's
`macrodebug` function which pretty-prints the macroexpansion using the
full formatter.

## Fork notes

This repository is a **fork** of
[`fnlfmt`](https://git.sr.ht/~technomancy/fnlfmt), originally written by Phil
Hagelberg and contributors. The upstream project is hosted on SourceHut;
GitHub's fork UI cannot link a repository to a non-GitHub upstream, so the
relationship is documented here and in the repository description instead.

Remote layout:

* `upstream` → <https://git.sr.ht/~technomancy/fnlfmt> (read-only reference)
* `origin` → <https://github.com/tokyob0t/fnlfmt>

### Divergence policy

* Defaults stay byte-for-byte compatible with upstream. New behavior is
  opt-in through configuration, never enabled by accident.
* All work happens on feature branches and lands on `main` through pull
  requests, even for small changes.
* Fork-specific changes are kept as isolated as possible so upstream patches
  stay easy to rebase:

      git fetch upstream
      git rebase upstream/main

## Contributing

For this fork, open an issue or pull request at
<https://github.com/tokyob0t/fnlfmt>.

Upstream contributions still go directly to the maintainer or the
[Fennel mailing list](https://lists.sr.ht/%7Etechnomancy/fennel).

Please see [my contributing guide](https://technomancy.us/contributing)
for more details.

## License

Copyright © 2019-2026 Phil Hagelberg and contributors

Released under the MIT license; see LICENSE.
