;; classify.fnl --- configurable classification of Fennel forms
;;
;; The formatter needs to know what kind of form a list is before it can
;; decide how to lay it out. The built-in table is derived from Fennel's
;; own syntax table plus a few naming conventions, and configuration can
;; replace or extend it without touching the formatting code.

(local fennel (require :fennel))

(local syntax (fennel.syntax))

(local styles [:call
               :body
               :binding
               :function
               :match
               :conditional
               :threading
               :sequence
               :block
               :maybe-body])

(local style-flags {:call {}
                    :body {:body? true}
                    :binding {:body? true :binding? true}
                    :function {:body? true :function? true}
                    :match {:body? true :match? true}
                    :conditional {:maybe-body? true
                                  :pairwise-if? true
                                  :one-per-line? true}
                    :threading {:maybe-body? true :one-per-line? true}
                    :sequence {:body? true :one-per-line? true}
                    :block {:body? true :force-newline? true}
                    :maybe-body {:maybe-body? true}})

(local fn-forms {:fn true :lambda true :λ true :macro true})
(local match-forms {:match true :case true :match-try true :case-try true})
(local block-forms {:do true :eval-compiler true})

;; Naming conventions inferred for third-party macros. They mirror the
;; heuristics fnlfmt has always used; `:infer-macros? false` turns them off.
(local default-patterns [["^fn/" :function]
                         ["^λ/" :function]
                         ["%.with-" :body]
                         ["^with-" :body]
                         ["%.def" :body]
                         ["^def" :body]])

(fn built-in-forms []
  (let [forms {}]
    (each [name props (pairs syntax)]
      (when props.body-form?
        (tset forms name (if props.binding-form? :binding
                             (. fn-forms name) :function
                             (. match-forms name) :match
                             (. block-forms name) :block
                             :body))))
    (set forms.if :conditional)
    (each [_ name (ipairs [:-> :->> :-?> :-?>>])]
      (tset forms name :threading))
    forms))

(local default-forms (built-in-forms))

(fn valid-style? [style]
  (not= nil (. style-flags style)))

(fn merge [base extra]
  (let [out {}]
    (each [key value (pairs base)]
      (tset out key value))
    (each [key value (pairs (or extra {}))]
      (tset out key value))
    out))

(fn combine [first second]
  (let [out []]
    (each [_ value (ipairs first)]
      (table.insert out value))
    (each [_ value (ipairs second)]
      (table.insert out value))
    out))

(fn build [?settings]
  "Return a classifier for the given settings. Configuration files are
already validated by `config`, so this only fills in defaults."
  (let [settings (or ?settings {})
        inference? (if (= nil settings.infer-macros?)
                       true
                       settings.infer-macros?)
        patterns (or settings.form-patterns [])
        patterns (if inference?
                     (combine patterns default-patterns)
                     patterns)]
    {:forms (merge (or settings.forms default-forms) settings.extra-forms)
     :patterns patterns
     :unknown (or settings.unknown-form-style :call)
     :indent (or settings.indent 2)
     :align-calls? (if (= nil settings.align-calls?)
                       true
                       settings.align-calls?)}))

(fn match-pattern [patterns callee]
  (accumulate [style nil _ pair (ipairs patterns) :until style]
    (when (string.find callee (. pair 1))
      (. pair 2))))

(fn style-of [classifier callee]
  (or (. classifier.forms callee) (match-pattern classifier.patterns callee)
      classifier.unknown))

(fn has-flag? [classifier callee flag]
  (let [style (style-of classifier callee)]
    (?. style-flags style flag)))

(fn body? [classifier callee]
  (has-flag? classifier callee :body?))

(fn binding? [classifier callee]
  (has-flag? classifier callee :binding?))

(fn function? [classifier callee]
  (has-flag? classifier callee :function?))

(fn match? [classifier callee]
  (has-flag? classifier callee :match?))

(fn conditional? [classifier callee]
  (has-flag? classifier callee :pairwise-if?))

(fn one-per-line? [classifier callee]
  (has-flag? classifier callee :one-per-line?))

(fn force-newline? [classifier callee]
  (has-flag? classifier callee :force-newline?))

(fn maybe-body? [classifier callee]
  (has-flag? classifier callee :maybe-body?))

{: styles
 : default-patterns
 : default-forms
 : valid-style?
 : build
 : style-of
 : body?
 : binding?
 : function?
 : match?
 : conditional?
 : one-per-line?
 : force-newline?
 : maybe-body?}
