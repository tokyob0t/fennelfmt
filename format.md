# How to Format Fennel Code

Fennel formatting follows the traditions of the lisps of the past;
seasoned lispers should not find any surprises (except perhaps the
Clojure-style preference for square brackets in binding positions
instead of doubled-up parens for `let`, etc). Formatting for tables
defers to the built-in `fennel.view` function, which *is* considered
canonical.

Key/value tables are shown with each key/value pair on its own line,
unless they are small enough to all fit on one line. Sequential tables
similarly have each element on their own line unless they fit all on a
single line. Tables with string keys and symbol values will use `{:
foo : bar}` shorthand notation where possible.

Comments that go after code on a line should have one semicolon, but
comments which start a line should have at least two; more can be used
for section headers. This is not currently enforced by `fnlfmt`.

There are three ways that calls (aka lists) can be formatted. The
default style used for functions and most macros is to put successive
arguments on the same line as the first, up till the point where the
arguments exceed 80 columns, at which a new line is started which
lines up with the first argument:

```fennel
(call-me-maybe included-data excluded-data filtering-function 
               extra-optional-data)
```

The second style is that of macros that take "body" arguments; for
example `let` or `when` treat their first argument specially, but then
all arguments past that are indented two spaces in.

```fennel
(let [escape? (and options.escape-newlines?
                   (< (length str) (- options.line-length indent)))
      escs (setmetatable codes {:__index #(: "\\%03d" :format ($2:byte))})]
  (when debug?
    (print "escaping string:" (fennel.view escs)))
  (.. "\"" (str:gsub "[%c\\\"]" escs) "\""))
```

The indentation for `fn` and `lambda` are similar, except they accept an
optional name before their arglist.

Third-party macros will be treated this way if their name starts with
`def`, `with-`, `fn/`, or `λ/`.

Finally `if` and the `case` family are treated differently; if possible it
will attempt to pair off their pattern/condition clauses with the body
on the same line. If that can't fit, it falls back to one-form-per-line.

```fennel
(case (pcall require :fnlfmt)
  (fmt-ok {: fnlfmt}) fnlfmt
  _ (->> (case (pcall require :fennel)
           (ok {: view}) view
           tostring)
         (warn "Failed to load fnlfmt; try checking package.path")))

(if (not b) nil
    done? (values true retval)
    (parse-loop (skip-whitespace (getb))))

;; [...]

            (if (break-pair? pair-wise? non-comment-count viewed
                             (. bindings (+ i 1)) (. bindings (+ i 2)) indent)
                (do
                  (table.insert out (.. "\n" (string.rep " " start-indent)))
                  (set indent start-indent))
                continue?
                (do
                  (set indent (+ indent 1 (last-line-length viewed)))
                  (table.insert out " ")))
```

## Sometimes It Depends

There are a handful of formatting choices where we must defer to
existing style decisions rather than enforcing one specific
choice. For example, the choice of whether to use `"this-style"`
string or `:this-style` is not one that can be determined
mechanically; it communicates human intent around whether the string
is used for its contents in the former case or whether it's used as an
opaque name the way a keyword/symbol/enum might in the latter case.
Similarly with numbers, sometimes hexadecimal notation will be more
appropriate for the task at hand, and sometimes underscores to
separate out thousands/millions/etc will improve readability. A
mechanical process like `fnlfmt` should not change this; it will
retain whatever formatting choices were present in the original input
where possible.

Certain forms which have a body are sometimes allowed to keep their
body on the same line as the call, if the original code has it that
way, provided the body doesn't nest more than two levels and fits in
the line length limit.

Top level forms may or may not have blank lines between them depending on
whether the input code spaces them out. Functions defined inside a
body form get empty lines spacing them out as well.

Similarly `if` forms and arrow forms will occasionally be allowed to
be one line if the original code had them as one-liners.
