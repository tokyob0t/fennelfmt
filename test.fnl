(local fmt (require :fnlfmt))
(local config (require :config))
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
    (let [(out code) (run (.. "./fnlfmt --no-config --check " clean))]
      (check :cli/check-clean (= 0 code)))
    (let [(out code) (run (.. "./fnlfmt --no-config --check " dirty))]
      (check :cli/check-dirty
             (and (= 1 code) (not= nil (out:find "Not formatted" 1 true)))))
    (let [(out code) (run (.. "./fnlfmt --no-config --check-indent " unindented))]
      (check :cli/check-indent-dirty (= 1 code)))
    (let [(out code) (run (.. "./fnlfmt --no-config --indent " indent-out))]
      (check :cli/indent-exact (and (= 0 code) (= out "(foo bar)\n"))))
    (let [(out code) (run (.. "./fnlfmt --no-config --indent " unindented))]
      (check :cli/indent-final-line
             (and (= 0 code) (not= nil (out:find "baz)" 1 true)))))
    (let [(out code) (run (.. "./fnlfmt --no-config --fix-indent " unindented))]
      (check :cli/fix-indent-final-line
             (and (= 0 code)
                  (not= nil (: (read unindented) :find "baz)" 1 true)))))
    (let [(out code) (run (.. "./fnlfmt --no-config --check " empty))]
      (check :cli/check-empty (= 0 code)))
    (run (.. "./fnlfmt --no-config --fix " empty))
    (check :cli/fix-empty (= "" (read empty))))
  (let [(out code) (run "./fnlfmt --help")]
    (check :cli/help (and (= 0 code) (not= nil (out:find "--indent" 1 true)))))
  (let [(out code) (run "./fnlfmt --version")]
    (check :cli/version (and (= 0 code)
                             (not= nil
                                   (out:find (.. "fnlfmt version " fmt.version)
                                             1 true))))))

(fn config-tests []
  (let [root (tmpdir)
        sub (.. root "/sub")
        long "(print (some-function with-three arguments here to test wrapping behavior ok fine))\n"]
    (os.execute (.. "mkdir -p '" sub "'"))
    (write-into root ".fnlfmt.fnl" "{:line-length 100}\n")
    (write-into sub ".fnlfmt.fnl" "{:line-length 60}\n")
    (write-into sub "x.fnl" "(foo bar)\n")
    (write-into root "long.fnl" long)
    ;; Nearest config wins; discovery walks up to the parent.
    (let [(settings _ path) (config.resolve (.. sub "/x.fnl") {})]
      (check :config/nearest-wins (= 60 settings.line-length))
      (check :config/nearest-path (= path (.. sub "/.fnlfmt.fnl"))))
    (let [(settings _ path) (config.resolve (.. root "/y.fnl") {})]
      (check :config/parent-found
             (and (= 100 settings.line-length)
                  (= path (.. root "/.fnlfmt.fnl")))))
    (let [(settings _ path) (config.resolve (.. sub "/x.fnl") {:no-config true})]
      (check :config/no-config (and (= 80 settings.line-length) (= nil path))))
    (let [(settings _ path) (config.resolve (.. sub "/x.fnl")
                                            {:config (.. root "/.fnlfmt.fnl")})]
      (check :config/explicit (= 100 settings.line-length)))
    ;; Command line options override the config file.
    (let [(settings _) (config.resolve (.. sub "/x.fnl")
                                       {:config (.. root "/.fnlfmt.fnl")
                                        :no-comments true})]
      (check :config/cli-precedence
             (and (= 100 settings.line-length) (= true settings.no-comments))))
    ;; --print-config shows the effective values and their provenance.
    (let [(out code) (run (.. "./fnlfmt --print-config '" (.. sub "/x.fnl") "'"))]
      (check :cli/print-config
             (and (= 0 code)
                  (not= nil (out:find (.. "config file: " sub "/.fnlfmt.fnl") 1
                                      true))
                  (not= nil (out:find ":line-length  60" 1 true)))))
    ;; FNLFMT_CONFIG takes precedence over discovered configs.
    (let [(out code) (run (.. "FNLFMT_CONFIG='" (.. root "/.fnlfmt.fnl")
                              "' ./fnlfmt --print-config '" (.. sub "/x.fnl")
                              "'"))]
      (check :cli/env-config
             (and (= 0 code) (not= nil (out:find ":line-length  100" 1 true)))))
    (let [(out code) (run (.. "FNLFMT_CONFIG='" (.. root "/.fnlfmt.fnl")
                              "' ./fnlfmt --no-config --print-config '"
                              (.. sub "/x.fnl") "'"))]
      (check :cli/env-config-overridden
             (and (= 0 code) (not= nil (out:find ":line-length  80" 1 true)))))
    ;; --config overrides FNLFMT_CONFIG.
    (let [(out code) (run (.. "FNLFMT_CONFIG='" (.. root "/.fnlfmt.fnl")
                              "' ./fnlfmt --config '" (.. sub "/.fnlfmt.fnl")
                              "' --print-config '" (.. sub "/x.fnl") "'"))]
      (check :cli/config-overrides-env
             (and (= 0 code) (not= nil (out:find ":line-length  60" 1 true)))))
    ;; :line-length changes how calls are wrapped.
    (let [(out code) (run (.. "./fnlfmt --no-config '" (.. root "/long.fnl")
                              "'"))]
      (check :cli/line-length-default
             (and (= 0 code) (not= nil (out:find "ok\n" 1 true)))))
    (let [(out code) (run (.. "./fnlfmt --config '" (.. root "/.fnlfmt.fnl")
                              "' '" (.. root "/long.fnl") "'"))]
      (check :cli/line-length-config (and (= 0 code) (= out long))))
    ;; :no-comments can be set from the config file.
    (write-into root ".fnlfmt.fnl" "{:no-comments true}\n")
    (write-into root "comments.fnl" "; hi\n(print 1)\n")
    (let [(out code) (run (.. "./fnlfmt '" (.. root "/comments.fnl") "'"))]
      (check :cli/config-no-comments (and (= 0 code) (= out "(print 1)\n")))
      ;; Validation fails with a location and a helpful message.
      (let [bad (write-into root ".fnlfmt.fnl" "{:version 2}\n")
            (out code) (run (.. "./fnlfmt --config '" bad "' --print-config"))]
        (check :config/bad-version
               (and (= 1 code)
                    (not= nil (out:find "unsupported configuration version 2" 1
                                        true)))))
      (let [bad (write-into root ".fnlfmt.fnl" "{:oops 1}\n")
            (out code) (run (.. "./fnlfmt --config '" bad "' --print-config"))]
        (check :config/unknown-key
               (and (= 1 code)
                    (not= nil (out:find "unknown configuration key :oops" 1
                                        true)))))
      (let [bad (write-into root ".fnlfmt.fnl" "{:line-length :big}\n")
            (out code) (run (.. "./fnlfmt --config '" bad "' --print-config"))]
        (check :config/wrong-type
               (and (= 1 code)
                    (not= nil (out:find ":line-length must be a number" 1 true)))))
      (let [bad (write-into root ".fnlfmt.fnl" "{:line-length 100\n :oops")
            (out code) (run (.. "./fnlfmt --config '" bad "' --print-config"))]
        (check :config/parse-error
               (and (= 1 code) (not= nil (out:find "Parse error" 1 true)))))
      (let [(out code) (run (.. "./fnlfmt --config '" (.. root "/missing.fnl")
                                "' --print-config"))]
        (check :config/missing-file
               (and (= 1 code)
                    (not= nil (out:find "configuration file not found" 1 true)))))
      ;; --config and --no-config are mutually exclusive.
      (let [(out code) (run "./fnlfmt --config x --no-config --print-config")]
        (check :config/mutually-exclusive
               (and (= 1 code)
                    (not= nil (out:find "mutually exclusive" 1 true)))))
      (os.execute (.. "rm -rf '" root "'")))))

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
  (config-tests))

(print (: "%s passed, %s failed" :format pass (length failures)))
(when (not= 0 (length failures))
  (print "Failures:" (table.concat failures ", "))
  (os.exit 1))
