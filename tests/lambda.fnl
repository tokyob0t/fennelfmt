(λ greet [name]
  "Returns a greeting for the given name."
  (.. "Hello, " name "!"))

;; fennelfmt: skip
(lambda print-greeting [greeting]
  "Prints a greeting."
  (print greeting))

(λ way-too-many-arguments [_first
                           _second
                           {: foo
                            : bar
                            : baz
                            : quux
                            :unused1 _
                            :unused2 _
                            :unused3 _
                            :unused4 _
                            & destructured}
                           another
                           last-param]
  "Lambda with way too many arguments."
  (.. "body omitted for " "brevity"))
