(local fmt (require :fnlfmt))
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

(fn cli-tests []
  (let [clean (tmpfile "(foo bar)\n")
        dirty (tmpfile "(foo   bar)\n")
        unindented (tmpfile "(foo\n1)\n(bar\n  baz)")
        empty (tmpfile "")
        indent-out (tmpfile "(foo bar)\n")]
    (let [(out code) (run (.. "./fnlfmt --check " clean))]
      (check :cli/check-clean (= 0 code)))
    (let [(out code) (run (.. "./fnlfmt --check " dirty))]
      (check :cli/check-dirty
             (and (= 1 code) (not= nil (out:find "Not formatted" 1 true)))))
    (let [(out code) (run (.. "./fnlfmt --check-indent " unindented))]
      (check :cli/check-indent-dirty (= 1 code)))
    (let [(out code) (run (.. "./fnlfmt --indent " indent-out))]
      (check :cli/indent-exact (and (= 0 code) (= out "(foo bar)\n"))))
    (let [(out code) (run (.. "./fnlfmt --indent " unindented))]
      (check :cli/indent-final-line
             (and (= 0 code) (not= nil (out:find "baz)" 1 true)))))
    (let [(out code) (run (.. "./fnlfmt --fix-indent " unindented))]
      (check :cli/fix-indent-final-line
             (and (= 0 code)
                  (not= nil (: (read unindented) :find "baz)" 1 true)))))
    (let [(out code) (run (.. "./fnlfmt --check " empty))]
      (check :cli/check-empty (= 0 code)))
    (run (.. "./fnlfmt --fix " empty))
    (check :cli/fix-empty (= "" (read empty))))
  (let [(out code) (run "./fnlfmt --help")]
    (check :cli/help (and (= 0 code) (not= nil (out:find "--indent" 1 true)))))
  (let [(out code) (run "./fnlfmt --version")]
    (check :cli/version (and (= 0 code)
                             (not= nil
                                   (out:find (.. "fnlfmt version " fmt.version)
                                             1 true))))))

(each [_ name (ipairs (if (< 0 (length arg))
                          arg
                          cases))]
  (let [filename (.. :tests/ name :.fnl)
        expected (read filename)
        actual (fmt.format-file filename {})
        actual-indent (indent.indent expected)]
    (if (and (= actual expected)
             (or (= actual-indent expected) (= filename "tests/skip.fnl")))
        (set pass (+ pass 1))
        (= actual expected)
        (failed name filename actual-indent)
        (failed name filename actual))))

(when (= 0 (length arg))
  (cli-tests))

(print (: "%s passed, %s failed" :format pass (length failures)))
(when (not= 0 (length failures))
  (print "Failures:" (table.concat failures ", "))
  (os.exit 1))
