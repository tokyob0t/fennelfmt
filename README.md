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

By design there is no way to configure it. When it comes to
indentation, the choices it makes should be correct other than bugs or
when new features are added to Fennel itself. When it comes to where
the line breaks are inserted, it tries its best, but there are
certainly cases where a human could do better. Sometimes when it comes
to line breaks it will defer to the existing code where possible.

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
  as such if their name starts with `with-` or `def`. Functions which
  use this naming convention will be indented like `let`.

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
