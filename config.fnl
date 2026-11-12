;; config.fnl --- configuration discovery and validation for fnlfmt
;;
;; Configuration is data, not code: it is parsed with Fennel's parser and
;; validated here, never evaluated. This keeps project configs safe to read
;; even when they come from an untrusted checkout.
;;
;; This is the single place where the project name used for config filenames
;; and environment variables lives, so renaming the project only requires
;; changing `project-name` below.

(local fennel (require :fennel))

(local project-name :fnlfmt)
(local config-filename (.. "." project-name ".fnl"))
(local user-config-filename (.. project-name "/config.fnl"))
(local env-var (.. (string.upper project-name) "_CONFIG"))

(local defaults {:version 1 :style :default :line-length 80 :no-comments false})

;; Presets bundle defaults for the options that are currently implemented.
;; New presets are added here as the rest of the option catalog lands.
(local presets {:default {}})

(local valid-keys {:version :number
                   :style :string
                   :line-length :number
                   :no-comments :boolean})

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

(fn user-config []
  (let [xdg (os.getenv "XDG_CONFIG_HOME")
        home (os.getenv "HOME")
        base (if (and xdg (not= "" xdg)) xdg
                 (and home (not= "" home)) (.. home "/.config"))]
    (when base
      (let [path (.. base "/" user-config-filename)]
        (when (file-exists? path) path)))))

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
              (error (.. loc ": :line-length must be an integer >= 20") 0))))))
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
                 (or (nearest-config (if (= filename "-")
                                         (or (os.getenv "PWD") ".")
                                         (dirname (absolute filename))))
                     (user-config)))
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
        order [:version :style :line-length :no-comments]
        width (accumulate [n 0 _ key (ipairs order)]
                (math.max n (length key)))
        lines [(.. "fnlfmt configuration for " filename)
               (.. "config file: " (or path "none"))]]
    (each [_ key (ipairs order)]
      (table.insert lines (.. "  :" key (string.rep " " (- width (length key)))
                              "  " (fennel.view (. settings key)) "  ("
                              (. source key) ")")))
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
