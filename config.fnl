;; config.fnl --- configuration discovery and validation for fennelfmt
;;
;; Configuration is data, not code: it is parsed with Fennel's parser and
;; validated here, never evaluated. This keeps project configs safe to read
;; even when they come from an untrusted checkout.
;;
;; This is the single place where the project name used for config filenames
;; and environment variables lives, so renaming the project only requires
;; changing `project-name` below.

(local fennel (require :fennel))
(local classify (require :classify))

(local project-name :fennelfmt)
(local config-filename (.. "." project-name ".fnl"))
(local env-var (.. (string.upper project-name) "_CONFIG"))

(local defaults {:version 1
                 :style :default
                 :line-length 80
                 :indent 2
                 :align-calls? true
                 :trailing-newline? true
                 :no-comments false
                 :extra-forms {}
                 :form-patterns []
                 :unknown-form-style :call
                 :infer-macros? true})

;; Presets bundle options that are commonly changed together. Explicit keys in
;; a config file or on the command line override the preset.
(local presets {:default {}
                :wide {:line-length 100}
                :block {:align-calls? false}})

(local valid-keys {:version :number
                   :style :string
                   :line-length :number
                   :indent :number
                   :align-calls? :boolean
                   :trailing-newline? :boolean
                   :no-comments :boolean
                   :forms :table
                   :extra-forms :table
                   :form-patterns :table
                   :unknown-form-style :string
                   :infer-macros? :boolean})

(fn file-exists? [path]
  (let [f (io.open path :r)]
    (if f
        (do
          (f:close)
          true)
        false)))

(fn dirname [path]
  (let [dir (path:match "^(.*)/[^/]*$")]
    (if (not dir) "."
        (= "" dir) "/"
        dir)))

(fn absolute [path]
  (if (path:match "^/")
      path
      (.. (or (os.getenv "PWD") ".") "/" path)))

(fn parent [dir]
  (if (= dir "/")
      nil
      (let [up (dir:match "^(.*)/[^/]+$")]
        (if (or (not up) (= "" up)) "/" up))))

(fn nearest-config [start]
  (var dir start)
  (var found nil)
  (while (and dir (not found))
    (let [candidate (.. dir "/" config-filename)]
      (when (file-exists? candidate)
        (set found candidate)))
    (set dir (parent dir)))
  found)

(local parse-cache {})

(fn parse-file [path]
  (let [file (or (io.open path :r) (error (.. "cannot read " path)))
        contents (file:read :*all)]
    (file:close)
    (let [parser (fennel.parser (fennel.stringStream contents) path)
          forms []]
      (each [ok? form parser]
        (if ok?
            (table.insert forms form)
            (error (tostring form) 0)))
      (case (length forms)
        0 {}
        1 (let [config (. forms 1)]
            (if (= :table (type config))
                config
                (error (.. path ": configuration must be a single table") 0)))
        _ (error (.. path ": configuration must be a single table") 0)))))

(fn load [path]
  (or (. parse-cache path) (let [config (parse-file path)]
                             (tset parse-cache path config)
                             config)))

(fn sorted-keys [tbl]
  (doto (icollect [key (pairs tbl)] key)
    (table.sort)))

(fn style-names []
  (table.concat (icollect [_ style (ipairs classify.styles)]
                  (.. ":" style)) " "))

(fn validate-forms [forms loc key]
  (each [name style (pairs forms)]
    (when (not= :string (type name))
      (error (.. loc ": :" key " keys must be strings, got " (type name)) 0))
    (when (not (classify.valid-style? style))
      (error (.. loc ": :" key " :" name " has unknown style "
                 (fennel.view style) "; valid styles: " (style-names))
             0))))

(fn validate-patterns [patterns loc]
  (each [i pair (ipairs patterns)]
    (when (or (not= :table (type pair)) (not= 2 (length pair)))
      (error (.. loc ": :form-patterns entry " i
                 " must be a [pattern style] pair") 0))
    (let [pattern (. pair 1)
          style (. pair 2)]
      (when (not= :string (type pattern))
        (error (.. loc ": :form-patterns entry " i
                   " pattern must be a string, got " (type pattern))
               0))
      (when (not (pcall string.find "" pattern))
        (error (.. loc ": :form-patterns entry " i
                   " is not a valid Lua pattern: " pattern) 0))
      (when (not (classify.valid-style? style))
        (error (.. loc ": :form-patterns entry " i " has unknown style "
                   (fennel.view style) "; valid styles: " (style-names))
               0)))))

(fn validate [config path]
  (let [source (fennel.ast-source config)
        loc (.. (or source.filename path) ":" (or source.line 1))]
    (each [key value (pairs config)]
      (let [kind (. valid-keys key)]
        (if (not kind)
            (error (.. loc ": unknown configuration key :" key "; valid keys: "
                       (table.concat (icollect [_ k (ipairs (sorted-keys valid-keys))]
                                       (.. ":" k))
                                     " ")) 0)
            (not= kind (type value))
            (error (.. loc ": :" key " must be a " kind ", got " (type value))
                   0)
            (= key :version)
            (when (not= 1 value)
              (error (.. loc ": unsupported configuration version " value
                         "; expected 1") 0))
            (= key :style)
            (when (not (. presets value))
              (error (.. loc ": unknown preset :" value "; available: :"
                         (table.concat (sorted-keys presets) " :"))
                     0))
            (= key :line-length)
            (when (or (not= value (math.floor value)) (< value 20))
              (error (.. loc ": :line-length must be an integer >= 20") 0))
            (= key :indent)
            (when (or (not= value (math.floor value)) (< value 1))
              (error (.. loc ": :indent must be an integer >= 1") 0))
            (or (= key :forms) (= key :extra-forms))
            (validate-forms value loc key)
            (= key :form-patterns)
            (validate-patterns value loc)
            (= key :unknown-form-style)
            (when (not (classify.valid-style? value))
              (error (.. loc ": unknown form style " (fennel.view value)
                         "; valid styles: " (style-names))
                     0))))))
  config)

(fn resolve [filename ?options]
  "Return the effective settings table, their provenance, and the config file
used (or nil). Later sources win over earlier ones: defaults, preset, config
file, command line."
  (let [options (or ?options {})
        _ (when (and options.config options.no-config)
            (error "--config and --no-config are mutually exclusive" 0))
        env-path (os.getenv env-var)
        path (if options.no-config nil options.config options.config
                 (and env-path (not= "" env-path)) env-path
                 (nearest-config (if (= filename "-")
                                     (or (os.getenv "PWD") ".")
                                     (dirname (absolute filename)))))
        _ (when (and path (not (file-exists? path)))
            (error (.. "configuration file not found: " path) 0))
        config (if path (validate (load path) path) {})
        preset-name (or config.style :default)
        preset (or (. presets preset-name) {})
        settings {}
        source {}]
    (each [key value (pairs defaults)]
      (tset settings key value)
      (tset source key "default"))
    (each [key value (pairs preset)]
      (tset settings key value)
      (tset source key (.. "preset :" preset-name)))
    (each [key value (pairs config)]
      (tset settings key value)
      (tset source key path))
    (each [key value (pairs options)]
      (when (. valid-keys key)
        (tset settings key value)
        (tset source key "command line")))
    (values settings source path)))

(fn describe [filename ?options]
  "Render the effective settings and where each one came from."
  (let [(settings source path) (resolve filename ?options)
        order [:version
               :style
               :line-length
               :indent
               :align-calls?
               :trailing-newline?
               :no-comments
               :forms
               :extra-forms
               :form-patterns
               :unknown-form-style
               :infer-macros?]
        width (accumulate [n 0 _ key (ipairs order)]
                (math.max n (length key)))
        lines [(.. "fennelfmt configuration for " filename)
               (.. "config file: " (or path "none"))]]
    (each [_ key (ipairs order)]
      (let [value (. settings key)
            rendered (if (= nil value) "built-in" (fennel.view value))
            origin (or (. source key) "built-in")]
        (table.insert lines
                      (.. "  :" key (string.rep " " (- width (length key)))
                          "  " rendered "  (" origin ")"))))
    (table.concat lines "\n")))

{: project-name
 : config-filename
 : env-var
 : defaults
 : presets
 : valid-keys
 : load
 : resolve
 : describe}
