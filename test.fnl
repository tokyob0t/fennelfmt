(local fmt (require :fennelfmt))
(local config (require :config))
(local diff (require :diff))
(local indent (require :indentation))

(local cases [:top
              :table
              :call
              :comprehension
              :body
              :misc
              :semicolon
              :match
              :binding
              :comment
              :sugar
              :skip
              :macro
              :if
              :lambda])

(var pass 0)

(fn read [filename]
  (let [f (assert (io.open filename :r))
        contents (f:read :*all)]
    (f:close)
    contents))

(fn write-file [filename contents]
  (with-open [f (assert (io.open filename :w))]
    (f:write contents)))

(local failures [])

(fn check [name ok?]
  (if ok?
      (set pass (+ pass 1))
      (do
        (table.insert failures name)
        (print :FAIL name))))

(fn failed [name filename actual]
  (table.insert failures name)
  (print :FAIL name)
  (let [p (io.popen (string.format "diff -u %s -" filename) :w)]
    (p:write actual)
    (p:close))
  (print "\n"))

;; Run a shell command and return its combined output and exit code.
(fn run [command]
  (let [outfile (os.tmpname)
        (ok how code) (os.execute (.. command " > '" outfile "' 2>&1"))
        code (if (= :number (type ok))
                 ok
                 (or code (if ok 0 1)))
        out (read outfile)]
    (os.remove outfile)
    (values out code)))

(fn tmpfile [contents]
  (let [filename (os.tmpname)]
    (write-file filename contents)
    filename))

(fn tmpdir []
  (let [filename (os.tmpname)]
    (os.remove filename)
    (let [(ok?) (os.execute (.. "mkdir -p '" filename "'"))]
      (assert ok?)
      filename)))

(fn write-into [dir name contents]
  (let [filename (.. dir "/" name)]
    (write-file filename contents)
    filename))

(fn cli-tests []
  (let [clean (tmpfile "(foo bar)\n")
        dirty (tmpfile "(foo   bar)\n")
        unindented (tmpfile "(foo\n1)\n(bar\n  baz)")
        empty (tmpfile "")
        indent-out (tmpfile "(foo bar)\n")]
    (let [(out code) (run (.. "./fennelfmt --no-config --check " clean))]
      (check :cli/check-clean (= 0 code)))
    (let [(out code) (run (.. "./fennelfmt --no-config --check " dirty))]
      (check :cli/check-dirty
             (and (= 1 code) (not= nil (out:find "Not formatted" 1 true)))))
    (let [(out code) (run (.. "./fennelfmt --no-config --check-indent "
                              unindented))]
      (check :cli/check-indent-dirty (= 1 code)))
    (let [(out code) (run (.. "./fennelfmt --no-config --indent " indent-out))]
      (check :cli/indent-exact (and (= 0 code) (= out "(foo bar)\n"))))
    (let [(out code) (run (.. "./fennelfmt --no-config --indent " unindented))]
      (check :cli/indent-final-line
             (and (= 0 code) (not= nil (out:find "baz)" 1 true)))))
    (let [(out code) (run (.. "./fennelfmt --no-config --fix-indent "
                              unindented))]
      (check :cli/fix-indent-final-line
             (and (= 0 code)
                  (not= nil (: (read unindented) :find "baz)" 1 true)))))
    (let [(out code) (run (.. "./fennelfmt --no-config --check " empty))]
      (check :cli/check-empty (= 0 code)))
    (run (.. "./fennelfmt --no-config --fix " empty))
    (check :cli/fix-empty (= "" (read empty))))
  (let [(out code) (run "./fennelfmt --help")]
    (check :cli/help (and (= 0 code) (not= nil (out:find "--indent" 1 true)))))
  (let [(out code) (run "./fennelfmt --version")]
    (check :cli/version (and (= 0 code)
                             (not= nil
                                   (out:find (.. "fennelfmt version "
                                                 fmt.version)
                                             1 true))))))

(fn config-tests []
  (let [root (tmpdir)
        sub (.. root "/sub")
        long "(print (some-function with-three arguments here to test wrapping behavior ok fine))\n"]
    (os.execute (.. "mkdir -p '" sub "'"))
    (write-into root ".fennelfmt.fnl" "{:line-length 100}\n")
    (write-into sub ".fennelfmt.fnl" "{:line-length 60}\n")
    (write-into sub "x.fnl" "(foo bar)\n")
    (write-into root "long.fnl" long)
    ;; Nearest config wins; discovery walks up to the parent.
    (let [(settings _ path) (config.resolve (.. sub "/x.fnl") {})]
      (check :config/nearest-wins (= 60 settings.line-length))
      (check :config/nearest-path (= path (.. sub "/.fennelfmt.fnl"))))
    (let [(settings _ path) (config.resolve (.. root "/y.fnl") {})]
      (check :config/parent-found
             (and (= 100 settings.line-length)
                  (= path (.. root "/.fennelfmt.fnl")))))
    (let [(settings _ path) (config.resolve (.. sub "/x.fnl") {:no-config true})]
      (check :config/no-config (and (= 80 settings.line-length) (= nil path))))
    (let [(settings _ path) (config.resolve (.. sub "/x.fnl")
                                            {:config (.. root "/.fennelfmt.fnl")})]
      (check :config/explicit (= 100 settings.line-length)))
    ;; Command line options override the config file.
    (let [(settings _) (config.resolve (.. sub "/x.fnl")
                                       {:config (.. root "/.fennelfmt.fnl")
                                        :no-comments true})]
      (check :config/cli-precedence
             (and (= 100 settings.line-length) (= true settings.no-comments))))
    ;; --print-config shows the effective values and their provenance.
    (let [(out code) (run (.. "./fennelfmt --print-config '" (.. sub "/x.fnl")
                              "'"))]
      (check :cli/print-config
             (and (= 0 code)
                  (not= nil (out:find (.. "config file: " sub "/.fennelfmt.fnl")
                                      1 true))
                  (not= nil (out:find ":line%-length%s+60")))))
    ;; FENNELFMT_CONFIG takes precedence over discovered configs.
    (let [(out code) (run (.. "FENNELFMT_CONFIG='" (.. root "/.fennelfmt.fnl")
                              "' ./fennelfmt --print-config '" (.. sub "/x.fnl")
                              "'"))]
      (check :cli/env-config
             (and (= 0 code) (not= nil (out:find ":line%-length%s+100")))))
    (let [(out code) (run (.. "FENNELFMT_CONFIG='" (.. root "/.fennelfmt.fnl")
                              "' ./fennelfmt --no-config --print-config '"
                              (.. sub "/x.fnl") "'"))]
      (check :cli/env-config-overridden
             (and (= 0 code) (not= nil (out:find ":line%-length%s+80")))))
    ;; --config overrides FENNELFMT_CONFIG.
    (let [(out code) (run (.. "FENNELFMT_CONFIG='" (.. root "/.fennelfmt.fnl")
                              "' ./fennelfmt --config '"
                              (.. sub "/.fennelfmt.fnl") "' --print-config '"
                              (.. sub "/x.fnl") "'"))]
      (check :cli/config-overrides-env
             (and (= 0 code) (not= nil (out:find ":line%-length%s+60")))))
    ;; :line-length changes how calls are wrapped.
    (let [(out code) (run (.. "./fennelfmt --no-config '" (.. root "/long.fnl")
                              "'"))]
      (check :cli/line-length-default
             (and (= 0 code) (not= nil (out:find "ok\n" 1 true)))))
    (let [(out code) (run (.. "./fennelfmt --config '"
                              (.. root "/.fennelfmt.fnl") "' '"
                              (.. root "/long.fnl") "'"))]
      (check :cli/line-length-config (and (= 0 code) (= out long))))
    ;; :no-comments can be set from the config file.
    (write-into root ".fennelfmt.fnl" "{:no-comments true}\n")
    (write-into root "comments.fnl" "; hi\n(print 1)\n")
    (let [(out code) (run (.. "./fennelfmt '" (.. root "/comments.fnl") "'"))]
      (check :cli/config-no-comments (and (= 0 code) (= out "(print 1)\n")))
      ;; Validation fails with a location and a helpful message.
      (let [bad (write-into root ".fennelfmt.fnl" "{:version 2}\n")
            (out code) (run (.. "./fennelfmt --config '" bad "' --print-config"))]
        (check :config/bad-version
               (and (= 1 code)
                    (not= nil (out:find "unsupported configuration version 2" 1
                                        true)))))
      (let [bad (write-into root ".fennelfmt.fnl" "{:oops 1}\n")
            (out code) (run (.. "./fennelfmt --config '" bad "' --print-config"))]
        (check :config/unknown-key
               (and (= 1 code)
                    (not= nil (out:find "unknown configuration key :oops" 1
                                        true)))))
      (let [bad (write-into root ".fennelfmt.fnl" "{:line-length :big}\n")
            (out code) (run (.. "./fennelfmt --config '" bad "' --print-config"))]
        (check :config/wrong-type
               (and (= 1 code)
                    (not= nil (out:find ":line-length must be a number" 1 true)))))
      (let [bad (write-into root ".fennelfmt.fnl" "{:line-length 100\n :oops")
            (out code) (run (.. "./fennelfmt --config '" bad "' --print-config"))]
        (check :config/parse-error
               (and (= 1 code) (not= nil (out:find "Parse error" 1 true)))))
      (let [(out code) (run (.. "./fennelfmt --config '"
                                (.. root "/missing.fnl") "' --print-config"))]
        (check :config/missing-file
               (and (= 1 code)
                    (not= nil (out:find "configuration file not found" 1 true)))))
      ;; --config and --no-config are mutually exclusive.
      (let [(out code) (run "./fennelfmt --config x --no-config --print-config")]
        (check :config/mutually-exclusive
               (and (= 1 code)
                    (not= nil (out:find "mutually exclusive" 1 true)))))
      ;; There is no user-level config file.
      (let [base (tmpdir)
            work (.. base "/work")
            xdg (.. base "/xdg")
            user-config (.. xdg "/fennelfmt/config.fnl")]
        (os.execute (.. "mkdir -p '" work "' '" xdg "/fennelfmt'"))
        (write-file user-config "{:line-length 100}\n")
        (write-into work "x.fnl" "(foo)\n")
        (let [(out code) (run (.. "XDG_CONFIG_HOME='" xdg
                                  "' ./fennelfmt --print-config '"
                                  (.. work "/x.fnl") "'"))]
          (check :config/no-user-config
                 (and (= 0 code) (not= nil (out:find ":line%-length%s+80"))
                      (not= nil (out:find "config file: none" 1 true)))))
        (os.execute (.. "rm -rf '" base "'")))
      (os.execute (.. "rm -rf '" root "'")))))

(fn classification-tests []
  (let [root (tmpdir)
        file (fn [name contents] (write-into root name contents))
        configure (fn [contents] (write-into root ".fennelfmt.fnl" contents))
        format (fn [filename] (run (.. "./fennelfmt '" filename "'")))
        expect-error (fn [name contents needle]
                       (let [path (write-into root ".fennelfmt.fnl" contents)
                             (out code) (run (.. "./fennelfmt --config '" path
                                                 "' --print-config"))]
                         (check name
                                (and (= 1 code)
                                     (not= nil (out:find needle 1 true))))))]
    ;; Extra classifications add to the built-in table.
    (let [f (file "twiddle.fnl"
                  "(twiddle alpha\n         beta\n         gamma)\n")]
      (let [(out code) (run (.. "./fennelfmt --no-config '" f "'"))]
        (check :classify/default-call
               (and (= 0 code) (= out "(twiddle alpha beta gamma)\n"))))
      (configure "{:extra-forms {:twiddle :body}}\n")
      (let [(out code) (format f)]
        (check :classify/extra-body
               (and (= 0 code) (= out "(twiddle alpha\n  beta\n  gamma)\n"))))
      (configure "{:form-patterns [[\"^twiddle\" :body]]}\n")
      (let [(out code) (format f)]
        (check :classify/pattern-body
               (and (= 0 code) (= out "(twiddle alpha\n  beta\n  gamma)\n"))))
      (configure "{:unknown-form-style :body}\n")
      (let [(out code) (format f)]
        (check :classify/unknown-body
               (and (= 0 code) (= out "(twiddle alpha\n  beta\n  gamma)\n")))))
    ;; :forms replaces the built-in table instead of extending it.
    (let [f (file "when.fnl" "(when true\n  (print 1)\n  (print 2))\n")]
      (configure "{:forms {}}\n")
      (let [(out code) (format f)]
        (check :classify/forms-replace
               (and (= 0 code) (= out "(when true (print 1) (print 2))\n")))))
    ;; User patterns are checked before the built-in conventions.
    (let [f (file "with.fnl"
                  "(with-foo alpha\n          beta\n          gamma)\n")]
      (configure "{:form-patterns [[\"^with-\" :call]]}\n")
      (let [(out code) (format f)]
        (check :classify/pattern-override
               (and (= 0 code) (= out "(with-foo alpha beta gamma)\n"))))
      (configure "{:infer-macros? false}\n")
      (let [(out code) (format f)]
        (check :classify/no-inference
               (and (= 0 code) (= out "(with-foo alpha beta gamma)\n")))))
    ;; The other styles map to the formatter's existing behaviors.
    (let [f (file "function.fnl" "(my-fn foo [x y]\n  (print x))\n")]
      (configure "{:extra-forms {:my-fn :function}}\n")
      (let [(out code) (format f)]
        (check :classify/function-style
               (and (= 0 code) (= out "(my-fn foo [x y]\n  (print x))\n")))))
    (let [f (file "binding.fnl" "(my-let [x 1 y 2]\n  (print x))\n")]
      (configure "{:extra-forms {:my-let :binding}}\n")
      (let [(out code) (format f)]
        (check :classify/binding-style
               (and (= 0 code) (= out "(my-let [x 1 y 2]\n  (print x))\n")))))
    ;; Classification also drives the heuristic indenter.
    (let [(result _) (indent.indent "(twiddle alpha\nbeta)\n"
                                    {:extra-forms {:twiddle :body}})]
      (check :classify/indent-body (= result "(twiddle alpha\n  beta)\n")))
    (let [f (file "indent.fnl" "(twiddle alpha\nbeta)\n")]
      (configure "{:extra-forms {:twiddle :body}}\n")
      (let [(out code) (run (.. "./fennelfmt --indent '" f "'"))]
        (check :classify/cli-indent
               (and (= 0 code) (= out "(twiddle alpha\n  beta)\n")))))
    ;; --print-config exposes the new keys.
    (configure "{:extra-forms {:twiddle :body} :unknown-form-style :body}\n")
    (let [(out code) (run (.. "./fennelfmt --print-config '"
                              (.. root "/twiddle.fnl") "'"))]
      (check :classify/print-config
             (and (= 0 code) (not= nil (out:find ":extra-forms" 1 true))
                  (not= nil (out:find "twiddle" 1 true))
                  (not= nil (out:find ":unknown-form-style" 1 true)))))
    (expect-error :classify/bad-form-style "{:extra-forms {:twiddle :bogus}}\n"
                  "unknown style")
    (expect-error :classify/bad-unknown-style "{:unknown-form-style :bogus}\n"
                  "unknown form style")
    (expect-error :classify/bad-pattern "{:form-patterns [[\"[\" :body]]}\n"
                  "not a valid Lua pattern")
    (expect-error :classify/bad-infer "{:infer-macros? 1}\n"
                  "must be a boolean")
    (os.execute (.. "rm -rf '" root "'"))))

(fn option-tests []
  (let [root (tmpdir)
        file (fn [name contents] (write-into root name contents))
        configure (fn [contents] (write-into root ".fennelfmt.fnl" contents))
        format (fn [filename] (run (.. "./fennelfmt '" filename "'")))
        long-call (.. "(some-function aaaaaaaaaaaaaaaaaaaaaaaa "
                      "bbbbbbbbbbbbbbbbbbbbbbbb " "cccccccccccccccccccccccc)\n")
        aligned (.. "(some-function aaaaaaaaaaaaaaaaaaaaaaaa "
                    "bbbbbbbbbbbbbbbbbbbbbbbb\n"
                    "               cccccccccccccccccccccccc)\n")
        block (.. "(some-function aaaaaaaaaaaaaaaaaaaaaaaa "
                  "bbbbbbbbbbbbbbbbbbbbbbbb\n" "  cccccccccccccccccccccccc)\n")]
    ;; Body indentation width.
    (let [f (file "indent.fnl" "(when true\n  (print 1))\n")]
      (configure "{:indent 4}\n")
      (let [(out code) (format f)]
        (check :options/indent
               (and (= 0 code) (= out "(when true\n    (print 1))\n")))))
    (let [(result _) (indent.indent "(when true\n(print 1))\n" {:indent 4})]
      (check :options/indent-library (= result "(when true\n    (print 1))\n")))
    ;; :indent controls body lines only; binding alignment depends on the
    ;; opening delimiter's column, so it must not move with :indent.
    (let [f (file "binding.fnl"
                  (.. "(local example {:field (let [my-value1 1\n"
                      (string.rep " " 28) "my-value2 2]\n" (string.rep " " 24)
                      "[my-value1 my-value2])})\n"))
          indent1 (.. "(local example {:field (let [my-value1 1\n"
                      (string.rep " " 29) "my-value2 2]\n" (string.rep " " 24)
                      "[my-value1 my-value2])})\n")
          indent4 (.. "(local example {:field (let [my-value1 1\n"
                      (string.rep " " 29) "my-value2 2]\n" (string.rep " " 27)
                      "[my-value1 my-value2])})\n")]
      (configure "{:indent 1}\n")
      (let [(out code) (format f)]
        (check :options/binding-indent1 (and (= 0 code) (= out indent1))))
      (configure "{:indent 4}\n")
      (let [(out code) (format f)]
        (check :options/binding-indent4 (and (= 0 code) (= out indent4)))))
    ;; One-per-line forms align under the first argument, independent of
    ;; :indent.
    (let [f (file "if.fnl" "(if condition\n  (do-a)\n  (do-b))\n")]
      (configure "{:indent 4}\n")
      (let [(out code) (format f)]
        (check :options/one-per-line-indent
               (and (= 0 code)
                    (= out "(if condition\n    (do-a)\n    (do-b))\n")))))
    ;; The same holds inside hashfn sugar.
    (let [f (file "hashfn.fnl"
                  (.. "(local x #(let [a 1\n" (string.rep " " 16) "b 2]\n"
                      (string.rep " " 12) "(+ a b)))\n"))
          expected (.. "(local x #(let [a 1\n" (string.rep " " 16) "b 2]\n"
                       (string.rep " " 11) "(+ a b)))\n")]
      (configure "{:indent 1}\n")
      (let [(out code) (format f)]
        (check :options/binding-hashfn (and (= 0 code) (= out expected)))))
    ;; Call wrapping: aligned (default) vs block-indented.
    (let [f (file "long.fnl" long-call)]
      (let [(out code) (run (.. "./fennelfmt --no-config '" f "'"))]
        (check :options/align-default (and (= 0 code) (= out aligned))))
      (configure "{:align-calls? false}\n")
      (let [(out code) (format f)]
        (check :options/align-block (and (= 0 code) (= out block))))
      (configure "{:style :block}\n")
      (let [(out code) (format f)]
        (check :options/preset-block (and (= 0 code) (= out block))))
      (configure "{:style :wide}\n")
      (let [(out code) (format f)]
        (check :options/preset-wide (and (= 0 code) (= out long-call)))))
    ;; Trailing newline control.
    (let [f (file "newline.fnl" "(print 1)\n")]
      (configure "{:trailing-newline? false}\n")
      (let [(out code) (format f)]
        (check :options/no-trailing-newline
               (and (= 0 code) (= out "(print 1)")))))
    (let [(result _) (indent.indent "(print 1)\n" {:trailing-newline? false})]
      (check :options/indent-no-trailing-newline (= result "(print 1)")))
    ;; The new options appear in --print-config.
    (configure "{:indent 4 :align-calls? false}\n")
    (let [(out code) (run (.. "./fennelfmt --print-config '"
                              (.. root "/long.fnl") "'"))]
      (check :options/print-config
             (and (= 0 code) (not= nil (out:find ":indent" 1 true))
                  (not= nil (out:find ":align-calls?" 1 true)))))
    ;; Validation.
    (let [path (write-into root ".fennelfmt.fnl" "{:indent 0}\n")
          (out code) (run (.. "./fennelfmt --config '" path "' --print-config"))]
      (check :options/bad-indent
             (and (= 1 code) (not= nil (out:find "integer >= 1" 1 true)))))
    (let [path (write-into root ".fennelfmt.fnl" "{:align-calls? 1}\n")
          (out code) (run (.. "./fennelfmt --config '" path "' --print-config"))]
      (check :options/bad-align
             (and (= 1 code) (not= nil (out:find "must be a boolean" 1 true)))))
    (os.execute (.. "rm -rf '" root "'"))))

(fn io-tests []
  ;; Diff library.
  (check :io/diff (= (diff.unified "(foo   bar)\n" "(foo bar)\n" "x.fnl")
                     (.. "--- a/x.fnl\n+++ b/x.fnl\n@@ -1,1 +1,1 @@\n"
                         "-(foo   bar)\n+(foo bar)\n")))
  (check :io/diff-identical (= "" (diff.unified "(foo)\n" "(foo)\n" "x")))
  (check :io/diff-insert
         (= (diff.unified "" "a\n" "x")
            "--- a/x\n+++ b/x\n@@ -0,0 +1,1 @@\n+a\n"))
  (check :io/diff-absolute
         (= (diff.unified "a\n" "b\n" "/tmp/x")
            "--- a/tmp/x\n+++ b/tmp/x\n@@ -1,1 +1,1 @@\n-a\n+b\n"))
  (let [root (tmpdir)
        clean (write-into root "clean.fnl" "(foo bar)\n")
        dirty (write-into root "dirty.fnl" "(foo   bar)\n")]
    (let [(out code) (run (.. "./fennelfmt --no-config --diff '" dirty "'"))]
      (check :io/diff-dirty
             (and (= 1 code) (not= nil (out:find "--- a/" 1 true))
                  (not= nil (out:find "-(foo   bar)" 1 true))
                  (not= nil (out:find "+(foo bar)" 1 true)))))
    (let [(out code) (run (.. "./fennelfmt --no-config --diff '" clean "'"))]
      (check :io/diff-clean (and (= 0 code) (= out ""))))
    (let [(out code) (run (.. "./fennelfmt --no-config --quiet --check '" dirty
                              "'"))]
      (check :io/quiet-check (and (= 1 code) (= out ""))))
    (let [(out code) (run (.. "./fennelfmt --no-config --check '" dirty "'"))]
      (check :io/check-message
             (and (= 1 code) (not= nil (out:find "Not formatted" 1 true)))))
    (let [(out code) (run (.. "./fennelfmt --no-config --quiet --check '" clean
                              "'"))]
      (check :io/quiet-clean (and (= 0 code) (= out ""))))
    (let [(out code) (run "./fennelfmt --no-config /no/such/file.fnl")]
      (check :io/missing-file
             (and (= 1 code)
                  (not= nil (out:find "No such file or directory" 1 true)))))
    (os.execute (.. "rm -rf '" root "'")))
  (let [(out code) (run "printf '(foo   bar)\\n' | ./fennelfmt --no-config --stdin")]
    (check :io/stdin (and (= 0 code) (= out "(foo bar)\n"))))
  (let [(out code) (run "printf '(foo   bar)\\n' | ./fennelfmt --no-config --stdin --diff")]
    (check :io/stdin-diff
           (and (= 1 code) (not= nil (out:find "--- a/stdin" 1 true)))))
  (let [(out code) (run "printf '(foo\\n1)\\n' | ./fennelfmt --no-config --stdin --indent")]
    (check :io/stdin-indent (and (= 0 code) (= out "(foo\n     1)\n"))))
  (let [(out code) (run "printf '(foo)\\n' | ./fennelfmt --stdin --fix")]
    (check :io/stdin-fix
           (and (= 1 code) (not= nil (out:find "cannot write to stdin" 1 true)))))
  (let [(out code) (run "./fennelfmt --stdin some.fnl")]
    (check :io/stdin-filename
           (and (= 1 code)
                (not= nil (out:find "--stdin cannot be combined" 1 true))))))

(fn comment-tests []
  (let [root (tmpdir)
        file (fn [name contents] (write-into root name contents))
        format (fn [filename]
                 (run (.. "./fennelfmt --no-config '" filename "'")))]
    ;; Several trailing comments align in one column.
    (let [f (file "align.fnl"
                  (.. "(local example {:value1 1 ;; one\n" (string.rep " " 16)
                      ":value100 100 ;; hundred\n" (string.rep " " 16)
                      ":value2 2 ;; two\n" (string.rep " " 16) ":value3 3})\n"))
          expected (.. "(local example {:value1 1" (string.rep " " 5)
                       ";; one\n" (string.rep " " 16)
                       ":value100 100 ;; hundred\n" (string.rep " " 16)
                       ":value2 2" (string.rep " " 5) ";; two\n"
                       (string.rep " " 16) ":value3 3})\n")]
      (let [(out code) (format f)]
        (check :comment/align (and (= 0 code) (= out expected)))))
    ;; The widest line may be the closing one; align with it too.
    (let [f (file "align-close.fnl"
                  (.. "(local example {:value1 1 ;; one\n"
                      "                :value100 100 ;; hundred\n"
                      "                :value2 2 ;; two\n"
                      "                :value3 3}) ;; end\n"))
          expected (.. "(local example {:value1 1     ;; one\n"
                       "                :value100 100 ;; hundred\n"
                       "                :value2 2     ;; two\n"
                       "                :value3 3})   ;; end\n")]
      (let [(out code) (format f)]
        (check :comment/align-closing (and (= 0 code) (= out expected)))))
    ;; A comment on its own line inside the table must not inflate the
    ;; alignment column for the trailing comments around it.
    (let [f (file "mixed.fnl"
                  (.. "{:value1 1 ;; one\n :value2 2 ;; two\n :value3 3\n"
                      " ;; own\n :value4 4 ;; four\n :value5 5}\n"))
          expected (.. "{:value1 1 ;; one\n :value2 2 ;; two\n :value3 3\n"
                       " ;; own\n :value4 4 ;; four\n :value5 5}\n")]
      (let [(out code) (format f)]
        (check :comment/own-line-no-inflation (and (= 0 code) (= out expected)))))
    ;; A single trailing comment stays on its pair's line.
    (let [f (file "single.fnl" "{:a 1 ;; one\n :b 2}\n")]
      (let [(out code) (format f)]
        (check :comment/single
               (and (= 0 code) (= out "{:a 1 ;; one\n :b 2}\n")))))
    ;; A comment on its own line stays on its own line.
    (let [f (file "own.fnl" "{:a 1\n ;; own\n :b 2}\n")]
      (let [(out code) (format f)]
        (check :comment/own-line
               (and (= 0 code) (= out "{:a 1\n ;; own\n :b 2}\n")))))
    ;; A comment after a top-level form stays attached to it.
    (let [f (file "top.fnl" "(print 1) ;; trailing\n")]
      (let [(out code) (format f)]
        (check :comment/top-level
               (and (= 0 code) (= out "(print 1) ;; trailing\n")))))
    (let [f (file "top-own.fnl" "(print 1)\n;; own\n(print 2)\n")]
      (let [(out code) (format f)]
        (check :comment/top-level-own
               (and (= 0 code) (= out "(print 1)\n;; own\n(print 2)\n")))))
    ;; And so does a comment after a closing table/call.
    (let [f (file "closing.fnl" "(local x {:a 1}) ;; final\n")]
      (let [(out code) (format f)]
        (check :comment/after-close
               (and (= 0 code) (= out "(local x {:a 1}) ;; final\n")))))
    ;; A semicolon inside a multi-line string is not a comment.
    (let [contents (.. "(fn example []\n"
                       "  \"Returns nil if the line doesn't open a form; in that case\n"
                       "the caller continues.\")\n")
          f (file "string.fnl" contents)]
      (let [(out code) (format f)]
        (check :comment/multiline-string (and (= 0 code) (= out contents)))))
    (os.execute (.. "rm -rf '" root "'"))))

(each [_ name (ipairs (if (< 0 (length arg))
                          arg
                          cases))]
  (let [filename (.. :tests/ name :.fnl)
        expected (read filename)
        actual (fmt.format-file filename {:no-config true})
        actual-indent (indent.indent expected)]
    (if (and (= actual expected)
             (or (= actual-indent expected) (= filename "tests/skip.fnl")))
        (set pass (+ pass 1))
        (= actual expected)
        (failed name filename actual-indent)
        (failed name filename actual))))

(when (= 0 (length arg))
  (cli-tests)
  (config-tests)
  (classification-tests)
  (option-tests)
  (io-tests)
  (comment-tests))

(print (: "%s passed, %s failed" :format pass (length failures)))
(when (not= 0 (length failures))
  (print "Failures:" (table.concat failures ", "))
  (os.exit 1))
