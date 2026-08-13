(local fennel (require :fennel))

(set debug.traceback fennel.traceback)

(local {: format-file : version} (require :fnlfmt))

(fn help []
  (print "Usage: fnlfmt [--no-comments] [--fix] [--check] FILENAME...")
  (print "With the --fix or --check argument, multiple files can be specified.")
  (print "With the --fix argument, formats all the files in-place;")
  (print "with the --check argument, only checks if all the files are formatted;")
  (print "otherwise prints the formatted file to stdout."))

(local options [])

(for [i (length arg) 1 -1]
  (when (= :--no-comments (. arg i))
    (set options.no-comments true)
    (table.remove arg i)))

(fn check-file [filename]
  (if (select 2 (format-file filename options))
      (io.stderr:write (string.format "Not formatted: %s\n" filename))
      true  ))

(fn check-files [filenames]
  (-> (accumulate [ok? true _ filename (ipairs filenames)]
        (and (check-file filename) ok?))
      (#(if $ 0 1))
      (os.exit)))

(fn fix [filename]
  (let [(new changed?) (format-file filename options)]
    (when changed? ; prevent unnecessary writes
      (let [f (assert (io.open filename :w))]
        (f:write new)
        (f:close)))))

(case arg
  [:--version] (print (.. "fnlfmt version " version))
  [:--fix & filenames] (each [_ filename (pairs filenames)] (fix filename))
  [:--indent & filenames] (each [_ filename (pairs filenames)]
                            (let [{: indent} (require :indentation)]
                              (with-open [f (io.open filename)]
                                (print (indent (f:read :*all))))))
  [:--check & filenames] (check-files filenames)
  (where (or [:--help] ["-?"] [:-h])) (help)
  [filename nil] (io.stdout:write (pick-values 1 (format-file filename options)))
  _ (help))
