(local fennel (require :fennel))

(set debug.traceback fennel.traceback)

(local config (require :config))
(local {: format-file : version} (require :fnlfmt))
(local {: indent-file} (require :indentation))

(fn help []
  (print "Usage: fnlfmt [--no-comments] [--fix|--check] FILENAME...")
  (print "       fnlfmt [--no-comments] --indent FILENAME")
  (print "       fnlfmt [--fix-indent|--check-indent] FILENAME...")
  (print "       fnlfmt --print-config [FILENAME]")
  (print "")
  (print "With --fix or --check, multiple files can be specified.")
  (print "With --fix, formats all the files in-place;")
  (print "with --check, only checks if all the files are formatted and exits")
  (print "non-zero if any file needs formatting;")
  (print "otherwise prints the formatted file to stdout.")
  (print "")
  (print "Configuration is read from the nearest .fnlfmt.fnl, from")
  (print "$FNLFMT_CONFIG, or from ~/.config/fnlfmt/config.fnl.")
  (print "")
  (print "The --indent family only fixes indentation, using heuristics instead")
  (print "of a full parser, which is useful for incomplete code in editors.")
  (print "")
  (print "  --no-comments   strip comments")
  (print "  --config PATH   use PATH instead of searching for a config file")
  (print "  --no-config     ignore all config files")
  (print "  --print-config  print the effective configuration and exit")
  (print "  --version       print the version")
  (print "  -h, --help      print this help"))

(local options {})

(var mode :format)
(local filenames [])
(var config-path nil)
(var no-config? false)
(var print-config? false)
(var show-help? false)
(var show-version? false)

(fn usage-error [message]
  (io.stderr:write (.. "fnlfmt: " message "\n\n"))
  (help)
  (os.exit 1))

(fn set-mode [new-mode]
  (when (not= :format mode)
    (usage-error (.. "only one of --fix, --check, --indent, --fix-indent, "
                     "and --check-indent can be given")))
  (set mode new-mode))

(var i 1)

(while (<= i (length arg))
  (let [a (. arg i)]
    (if (= a "--no-comments")
        (set options.no-comments true)
        (= a "--config")
        (let [path (. arg (+ i 1))]
          (if path
              (do
                (set config-path path)
                (set i (+ i 1)))
              (usage-error "--config requires a path")))
        (= a "--no-config")
        (set no-config? true)
        (= a "--print-config")
        (set print-config? true)
        (= a "--fix")
        (set-mode :fix)
        (= a "--check")
        (set-mode :check)
        (= a "--indent")
        (set-mode :indent)
        (= a "--fix-indent")
        (set-mode :fix-indent)
        (= a "--check-indent")
        (set-mode :check-indent)
        (= a "--version")
        (set show-version? true)
        (or (= a "--help") (= a "-h") (= a "-?"))
        (set show-help? true)
        (= a "--")
        (do
          (set i (+ i 1))
          (while (<= i (length arg))
            (table.insert filenames (. arg i))
            (set i (+ i 1)))
          (set i (- i 1)))
        (if (and (< 1 (length a)) (= "-" (a:sub 1 1)))
            (usage-error (.. "unknown option " a))
            (table.insert filenames a))))
  (set i (+ i 1)))

(when config-path
  (set options.config config-path))

(when no-config?
  (set options.no-config true))

(fn check-file [filename f]
  (if (select 2 (f filename options))
      (do
        (io.stderr:write (string.format "Not formatted: %s\n" filename))
        false)
      true))

(fn check-files [filenames f]
  (-> (accumulate [ok? true _ filename (ipairs filenames)]
        (and (check-file filename f) ok?))
      (#(if $ 0 1))
      (os.exit)))

(fn fix [filename f]
  (let [(new changed?) (f filename options)]
    (when changed? ; prevent unnecessary writes
      (let [f (assert (io.open filename :w))]
        (f:write new)
        (f:close)))))

(fn format-file-to-stdout [filename]
  (io.stdout:write (pick-values 1 (format-file filename options))))

(fn main []
  (if show-help?
      (do
        (help)
        (os.exit 0))
      show-version?
      (do
        (print (.. "fnlfmt version " version))
        (os.exit 0))
      print-config?
      (do
        (print (config.describe (or (. filenames 1) ".") options))
        (os.exit 0))
      (do
        (when (= 0 (length filenames))
          (usage-error "no filenames given"))
        (case mode
          :fix (each [_ filename (ipairs filenames)]
                 (fix filename format-file))
          :check (check-files filenames format-file)
          :indent (do
                    (when (not= 1 (length filenames))
                      (usage-error "--indent takes exactly one filename"))
                    (io.stdout:write (pick-values 1
                                                  (indent-file (. filenames 1)
                                                               options))))
          :fix-indent (each [_ filename (ipairs filenames)]
                        (fix filename indent-file))
          :check-indent (check-files filenames indent-file)
          _ (do
              (when (not= 1 (length filenames))
                (usage-error "expected exactly one filename"))
              (format-file-to-stdout (. filenames 1)))))))

(let [(ok? err) (pcall main)]
  (when (not ok?)
    (io.stderr:write (.. "fnlfmt: " (tostring err) "\n"))
    (os.exit 1)))
