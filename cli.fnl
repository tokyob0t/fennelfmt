(local fennel (require :fennel))

(set debug.traceback fennel.traceback)

(local {: format-file : version} (require :fnlfmt))
(local {: indent-file} (require :indentation))

(fn help []
  (print "Usage: fnlfmt [--no-comments] [--fix|--check] FILENAME...")
  (print "       fnlfmt [--no-comments] --indent FILENAME")
  (print "       fnlfmt [--fix-indent|--check-indent] FILENAME...")
  (print "")
  (print "With --fix or --check, multiple files can be specified.")
  (print "With --fix, formats all the files in-place;")
  (print "with --check, only checks if all the files are formatted and exits")
  (print "non-zero if any file needs formatting;")
  (print "otherwise prints the formatted file to stdout.")
  (print "")
  (print "The --indent family only fixes indentation, using heuristics instead")
  (print "of a full parser, which is useful for incomplete code in editors.")
  (print "")
  (print "  --no-comments   strip comments")
  (print "  --version       print the version")
  (print "  -h, --help      print this help"))

(local options [])

(for [i (length arg) 1 -1]
  (when (= :--no-comments (. arg i))
    (set options.no-comments true)
    (table.remove arg i)))

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

(case arg
  [:--version] (print (.. "fnlfmt version " version))
  [:--fix & filenames] (each [_ filename (ipairs filenames)]
                         (fix filename format-file))
  [:--check & filenames] (check-files filenames format-file)
  [:--indent filename nil]
  (io.stdout:write (pick-values 1 (indent-file filename)))
  [:--fix-indent & filenames] (each [_ filename (ipairs filenames)]
                                (fix filename indent-file))
  [:--check-indent & filenames] (check-files filenames indent-file)
  (where (or [:--help] ["-?"] [:-h])) (help)
  [filename nil] (io.stdout:write (pick-values 1 (format-file filename options)))
  _ (help))
