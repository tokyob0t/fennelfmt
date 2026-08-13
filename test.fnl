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

(local failures [])

(fn failed [name filename actual]
  (table.insert failures name)
  (print :FAIL name)
  (let [p (io.popen (string.format "diff -u %s -" filename) :w)]
    (p:write actual)
    (p:close))
  (print "\n"))

(each [_ name (ipairs (if (< 0 (length arg))
                          arg
                          cases))]
  (let [filename (.. :tests/ name :.fnl)
        expected (read filename)
        actual (fmt.format-file filename {})
        actual-indent (indent.indent expected)]
    (if (and (= actual expected)
             (or (= actual-indent expected)
                 (= filename "tests/skip.fnl")))
        (set pass (+ pass 1))
        (= actual expected)
        (failed name filename actual-indent)
        (failed name filename actual))))

(print (: "%s passed, %s failed" :format pass (length failures)))
(when (not= 0 (length failures))
  (print "Failures:" (table.concat failures ", "))
  (os.exit 1))
