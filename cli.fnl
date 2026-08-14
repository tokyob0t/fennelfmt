(local fennel (require :fennel))

(set debug.traceback fennel.traceback)

(local {: format-file : version} (require :fnlfmt))
(local {: indent-file} (require :indentation))

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

(fn check-file [filename f]
  (if (select 2 (f filename options))
      (io.stderr:write (string.format "Not formatted: %s\n" filename))
      true  ))

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
  [:--fix & filenames] (each [_ filename (pairs filenames)]
                         (fix filename format-file))
  [:--check & filenames] (check-files filenames format-file)
  [:--indent filename nil] (print (indent-file filename))
  [:--fix-indent & filenames] (each [_ filename (pairs filenames)]
                                (fix filename indent-file))
  [:--check-indent & filenames] (check-files filenames indent-file)
  (where (or [:--help] ["-?"] [:-h])) (help)
  [filename nil] (io.stdout:write (pick-values 1 (format-file filename options)))
  _ (help))
