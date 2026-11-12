;;; fennelfmt.fnl --- The Fennel Formatter

;; https://git.sr.ht/~technomancy/fnlfmt

;; SPDX-License-Identifier: MIT
;; SPDX-FileCopyrightText: Phil Hagelberg and contributors

;; The basic idea is to run the code thru the parser, set a few overrides on the
;; __fennelview metamethods of the AST, then run it thru the fennel.view
;; pretty-printer. The bulk of this file consists of metamethods for lists and
;; tables which improve on fennel.view's existing logic of how to indent and
;; where to place newlines.

(local fennel (require :fennel))
(local config (require :config))
(local classify (require :classify))
(local unpack (or table.unpack _G.unpack))

(local raw-mt {:__fennelview #$.raw :__tostring #$.raw})

;; `tostring` on a Fennel list re-enters fennel.view without our options,
;; so fall back to the classifier of the formatting run in progress.
(var current-classifier nil)

;; Source lines of the file being formatted, used to tell whether a comment
;; shared a line with code. Nil when fennelfmt is called directly on an AST.
(var current-source-lines nil)

(fn inspector-classifier [inspector]
  (or inspector.classifier current-classifier))

(fn string? [ast]
  (and (= raw-mt (getmetatable ast)) (= :string (type ast.value))))

(fn number? [ast]
  (and (= raw-mt (getmetatable ast)) (= :number (type ast.value))))

(fn line [ast]
  (if (= raw-mt (getmetatable ast))
      ast.line
      (. (fennel.ast-source ast) :line)))

(fn end-line [ast]
  (if (= raw-mt (getmetatable ast))
      ast.line
      (let [source (fennel.ast-source ast)]
        (or (. source :endline) (. source :line) (line ast)))))

(fn last-line-length [line]
  (length (line:match "[^\n]*$")))

(fn split-lines [text]
  (let [lines []]
    (var pos 1)
    (while (<= pos (length text))
      (let [newline (string.find text "\n" pos true)]
        (if newline
            (do
              (table.insert lines (string.sub text pos (- newline 1)))
              (set pos (+ newline 1)))
            (do
              (table.insert lines (string.sub text pos))
              (set pos (+ (length text) 1))))))
    lines))

(fn find-comment [line in-string?]
  "Scan a line for a comment start. Returns the column and the string state
at the end of the line, so multi-line strings are not mistaken for comments."
  (var in-string? in-string?)
  (var escaped? false)
  (var pos 1)
  (var found nil)
  (while (and (<= pos (length line)) (not found))
    (let [char (string.sub line pos pos)]
      (if in-string?
          (if escaped? (set escaped? false)
              (= char "\\") (set escaped? true)
              (= char "\"") (set in-string? false))
          (= char "\"")
          (set in-string? true)
          (= char ";")
          (set found pos)))
    (set pos (+ pos 1)))
  (values found in-string?))

(fn trim-right [text]
  (string.gsub text "%s+$" ""))

(fn ends-with-opener? [text]
  (let [last-char (string.sub text -1)]
    (or (= last-char "[") (= last-char "{") (= last-char "("))))

(fn newline-count [text]
  (select 2 (string.gsub text "\n" "")))

(fn excluded-output-lines [out skipped-elements]
  "Map output line numbers covered by verbatim `;; fennelfmt: skip` slices."
  (let [excluded {}]
    (var line 1)
    (each [index text (ipairs out)]
      (let [count (newline-count text)]
        (when (. skipped-elements index)
          (for [i line (+ line count)]
            (tset excluded i true)))
        (set line (+ line count 1))))
    excluded))

(fn align-comment-runs [text ?excluded]
  "Align trailing comments on consecutive lines to one common column.
Own-line comments, comments directly after an opening delimiter, and lines
inside skipped forms break a run and are left untouched."
  (let [lines (split-lines text)
        excluded (or ?excluded {})
        trailing? (= "\n" (string.sub text -1))]
    (var run [])
    (var in-string? false)

    (fn flush []
      (when (< 0 (length run))
        (let [width (accumulate [width 0 _ item (ipairs run)]
                      (math.max width (length item.code)))]
          (each [_ item (ipairs run)]
            (tset lines item.line
                  (.. item.code (string.rep " " (- width (length item.code)))
                      " " item.comment))))
        (set run [])))

    (each [i line (ipairs lines)]
      (let [(start next-state) (find-comment line in-string?)]
        (set in-string? next-state)
        (if (. excluded i)
            (flush)
            (if start
                (let [prefix (string.sub line 1 (- start 1))
                      code (trim-right prefix)]
                  (if (and (code:match "%S") (not (ends-with-opener? code)))
                      (table.insert run
                                    {:line i
                                     :code code
                                     :comment (string.sub line start)})
                      (flush)))
                (flush)))))
    (flush)
    (let [result (table.concat lines "\n")]
      (if (and trailing? (not= "" result))
          (.. result "\n")
          result))))

(fn comment-trailing? [c previous-line]
  "True when comment shared a line with code. Falls back to comparing its
line with the previous value's line when no source text is available."
  (let [comment-line (line c)]
    (if (and comment-line current-source-lines)
        (let [source (. current-source-lines comment-line)
              text (tostring c)
              start (and source (string.find source text 1 true))]
          (when start
            (let [prefix (source:sub 1 (- start 1))]
              (not= nil (prefix:match "%S")))))
        (and previous-line (= previous-line comment-line)))))

(fn any? [tbl pred]
  (accumulate [found false _ v (pairs tbl) :until found]
    (not (not (pred v)))))

(fn strip-comments [t]
  (icollect [_ x (ipairs t)]
    (when (not (fennel.comment? x))
      x)))

(fn view-fn-args [t view inspector indent start-indent out]
  "Named functions need their name and arglists to be on the first line.
Returns the index of where the body of the function starts."
  (if (fennel.sym? (. t 2))
      (let [third (view (. t 3) inspector (+ indent 1))]
        (table.insert out " ")
        (table.insert out third)
        (if (and (string? (. t 4)) (. t 5))
            (do
              (table.insert out (.. "\n" (string.rep " " start-indent)))
              (set inspector.escape-newlines? false)
              (table.insert out (view (. t 4) inspector start-indent))
              (set inspector.escape-newlines? true)
              5)
            4))
      3))

(fn first-thing-in-line? [out]
  (let [last (or (. out (length out)) "")]
    (not (: (last:match "[^\n]*$") :match "[^ ]"))))

(fn break-pair? [inspector let? count viewed next-ast next-next indent]
  (if let?
      (and (= 1 (math.fmod count 2))
           (not (and (fennel.comment? next-ast)
                     ; does the trailing comment fit?
                     (<= (+ indent 1 (last-line-length viewed) 1
                            (length (tostring next-ast)))
                         inspector.line-length))))
      ;; if it's not a let, it's probably an iterator binding
      (and (or (string? next-ast) (: (tostring next-ast) :find "^&"))
           (< inspector.line-length
              (+ indent 1 (last-line-length viewed) 1
                 (length (tostring next-ast))
                 (length (fennel.view next-next
                                      {:classifier (inspector-classifier inspector)})))))))

(fn binding-comment [inspector c indent out start-indent]
  (when (and (< inspector.line-length (+ indent (length (tostring c))))
             (: (. out (length out)) :match "^[^%s]"))
    (table.insert out (.. "\n" (string.rep " " start-indent))))
  (when (and (not (first-thing-in-line? out)) (not= (length out) 1))
    (table.insert out " "))
  (table.insert out (tostring c))
  (table.insert out (.. "\n" (string.rep " " start-indent))))

(fn view-binding [bindings view inspector start-indent pair-wise? open close]
  "Binding sequences need special care; regular sequence assumptions don't work.
We want everything to be on one line as much as possible, (except for let)."
  (let [out [open]]
    (var (indent offset non-comment-count) (values start-indent 0 1))
    (for [i 1 (length bindings)]
      (while (fennel.comment? (. bindings (+ i offset)))
        ;; when a binding has a comment in it, emit it but don't let it throw
        ;; off the name/value pair counting
        (binding-comment inspector (. bindings (+ i offset)) indent out
                         start-indent)
        (set (indent offset) (values start-indent (+ offset 1))))
      (let [i (+ offset i)
            viewed (view (. bindings i) inspector indent)]
        (when (<= i (length bindings))
          (table.insert out viewed)
          (set non-comment-count (+ non-comment-count 1))
          (when (< i (length bindings))
            (if (break-pair? inspector pair-wise? non-comment-count viewed
                             (. bindings (+ i 1)) (. bindings (+ i 2)) indent)
                (do
                  (table.insert out (.. "\n" (string.rep " " start-indent)))
                  (set indent start-indent))
                (do
                  (set indent (+ indent 1 (last-line-length viewed)))
                  (table.insert out " ")))))))
    (table.insert out close)
    (table.concat out)))

(local slength (or (-?> (rawget _G :utf8) (. :len))
                   ;; utf8-len from from fennel.view
                   #(accumulate [n 0 _ (string.gmatch $
                                                      "[%z\001-\127\192-\247]")]
                      (+ n 1))))

(fn view-init-body [t view inspector list-indent body-indent out callee]
  "Certain forms need special handling of their first few args. Returns the
number of handled arguments."
  (let [classifier (inspector-classifier inspector)
        force? (classify.force-newline? classifier callee)]
    (if force? (table.insert out (.. "\n" (string.rep " " body-indent)))
        (not= nil (. t 2)) (table.insert out " "))
    (let [;; The column where the second argument begins, independent of the
          ;; body indentation width. Body forms still use body-indent for their
          ;; own lines and for forced newlines.
          arg-indent (if force?
                         body-indent
                         (+ list-indent 1 (slength callee) 1))
          ;; the handling of function args is very messy; sometimes they are
          ;; handled here and sometimes they're down in view-fn-args; kinda bad.
          second (if (and (classify.binding? classifier callee)
                          (not= :unquote (tostring (. t 2 1))))
                     (view-binding (. t 2) view inspector (+ arg-indent 1)
                                   (= :let callee)
                                   (if (fennel.list? (. t 2))
                                       (values "(" ")")
                                       (values "[" "]")))
                     (view (. t 2) inspector arg-indent))
          indent2 (+ arg-indent (length (second:match "[^\n]*$")))]
      (when (not= nil (. t 2))
        (table.insert out second))
      (if (classify.function? classifier callee)
          (view-fn-args t view inspector indent2 body-indent out)
          3))))

(fn match-same-line? [inspector callee i out viewed t]
  ;; just don't even try if there's comments!
  (and (classify.match? (inspector-classifier inspector) callee)
       (= 0 (math.fmod i 2)) (not (any? t fennel.comment?))
       (<= (+ (or (string.find viewed "\n") (length (viewed:match "[^\n]*$")))
              1 (last-line-length (. out (length out))))
           inspector.line-length)))

(fn trailing-comment? [inspector viewed body-indent]
  (and (viewed:match "^; ") (<= body-indent inspector.line-length)))

(fn fn-definition-pattern? [str]
  (or (str:match "^ *%(fn [^%[]") (str:match "^ *%(fn/")
      (str:match "^ *%(λ [^%[]") (str:match "^ *%(λ/")))

(fn space-out-fns? [prev viewed start-index i]
  ;; functions inside a body form shouldn't be spaced if they're the first thing
  (and (not (= start-index i))
       (or (fn-definition-pattern? prev) (fn-definition-pattern? viewed))))

(fn originally-same-lines? [t n1 n2]
  (let [first (. t n1)
        second (. t n2)]
    (and (= :table (type second)) (= (line t) (line first) (line second)))))

(fn scalar? [form]
  (or (not= :table (type form)) (fennel.sym? form) (fennel.comment? form)
      (fennel.varg? form) (string? form) (number? form)))

(fn depth [form base]
  (if (scalar? form)
      base
      (accumulate [d (+ base 1) _ elem (pairs form)]
        (math.max d (depth elem (+ base 1))))))

(fn preserve-same-line? [inspector t i indent out viewed depth]
  (and (<= (+ indent (length (table.concat out)) (length viewed))
           inspector.line-length) (<= depth 3)
       (not (fennel.comment? (. t (- i 1)))) (originally-same-lines? t 1 i)
       (not (viewed:find "\n"))))

(fn view-body [t view inspector list-indent out callee]
  "Insert arguments to a call to a special that takes body arguments."
  (let [classifier (inspector-classifier inspector)
        body-indent (+ list-indent classifier.indent)
        start-index (view-init-body t view inspector list-indent body-indent
                                    out callee)
        ;; do and if don't actually have special indentation but they do need
        ;; a newline after every form, so we can't use normal call formatting
        indent (if (classify.one-per-line? classifier callee)
                   (+ list-indent (length callee) 2)
                   body-indent)]
    (for [i (or start-index (+ (length t) 1)) (length t)]
      (let [viewed (view (. t i) inspector indent)
            body-indent (+ indent 1 (last-line-length (. out (length out))))]
        (if (or (match-same-line? inspector callee i out viewed t)
                (preserve-same-line? inspector t i indent out viewed
                                     (depth t 0))
                (trailing-comment? inspector viewed body-indent))
            (do
              (table.insert out " ")
              (table.insert out (view (. t i) inspector body-indent)))
            (do
              (when (space-out-fns? (. out (length out)) viewed start-index i)
                (table.insert out "\n"))
              (table.insert out (.. "\n" (string.rep " " indent)))
              (table.insert out viewed)))))))

(fn line-exceeded? [inspector indent viewed]
  (< inspector.line-length (+ indent (last-line-length viewed))))

(fn view-with-newline [view inspector out t i start-indent]
  (when (= " " (. out (length out)))
    (table.remove out))
  (table.insert out (.. "\n" (string.rep " " start-indent)))
  (let [viewed (view (. t i) inspector start-indent)]
    (table.insert out viewed)
    (+ start-indent (length (viewed:match "[^\n]*$")))))

(fn view-call [t view inspector indent0 out ?wrap-indent]
  "Insert arguments to a normal function call. "
  (let [wrap-indent (or ?wrap-indent indent0)]
    (var indent indent0)
    (for [i 2 (length t)]
      (table.insert out " ")
      (set indent (+ indent 1))
      (let [viewed (view (. t i) inspector (- indent 1))]
        ;; Attempt to fit as many args on a single line until it gets too long.
        (if (or (fennel.comment? (. t (- i 1)))
                (and (line-exceeded? inspector indent viewed) (not= 2 i)))
            (set indent (view-with-newline view inspector out t i wrap-indent))
            (do
              (table.insert out viewed)
              (set indent (+ indent (length (viewed:match "[^\n]*$"))))))))))

(fn view-pairwise-if [t view inspector indent out]
  (table.insert out (.. " "
                        (view-binding [(select 2 (unpack t))] view inspector
                                      indent true "" ""))))

(fn if-pair [view a b c]
  (.. (view a) " " (view b) (if (fennel.comment? c) (.. " " (view c)) "")))

(fn pairwise-if? [inspector t indent i view]
  (if (< (length (strip-comments t)) 5) false
      (not (classify.conditional? (inspector-classifier inspector)
                                  (tostring (. t 1)))) false
      (not (. t i)) true
      (< inspector.line-length
         (+ indent 1 (length (if-pair view (select i (unpack t)))))) false
      (pairwise-if? inspector t indent
                    (if (fennel.comment (. t (+ i 2)))
                        (+ i 3)
                        (+ i 2)) view)))

(fn view-maybe-body [t view inspector indent start-indent out callee wrap]
  (if (pairwise-if? inspector t indent 2 view)
      (view-pairwise-if t view inspector indent out)
      (not (originally-same-lines? t 2 3))
      (view-body t view inspector start-indent out callee)
      (view-call t view inspector indent out wrap)))

(fn newline-if-ends-in-comment [out indent]
  (when (: (. out (length out)) :match "^ *;[^\n]*$")
    (table.insert out (.. "\n" (string.rep " " indent)))))

(local sugars {:hashfn "#" :quote "`" :unquote ","})

(fn sweeten [t view inspector indent]
  (.. (. sugars (tostring (. t 1))) (view (. t 2) inspector (+ indent 1))))

(local renames {"#" :length "~=" :not= :lambda "λ"})

(fn view-list [t view inspector start-indent]
  (if (. sugars (tostring (. t 1)))
      (sweeten t view inspector start-indent)
      (let [classifier (inspector-classifier inspector)
            callee (view (. t 1) inspector (+ start-indent 1))
            callee (or (. renames callee) callee)
            out ["(" callee]
            body? (classify.body? classifier callee)
            align-indent (+ start-indent (length callee) 2)
            block-indent (+ start-indent classifier.indent)
            indent (if body? block-indent
                       (callee:find "\n") (+ (last-line-length callee) 1)
                       align-indent)
            wrap (if classifier.align-calls? indent block-indent)]
        ;; indent differently if it's calling a special form with body args
        (if body?
            (view-body t view inspector start-indent out callee)
            ;; in some cases we treat it differently depending on whether the
            ;; original code was multi-line or not
            (classify.maybe-body? classifier callee)
            (view-maybe-body t view inspector indent start-indent out callee
                             wrap)
            (view-call t view inspector indent out wrap))
        (newline-if-ends-in-comment out (if body? indent wrap))
        (table.insert out ")")
        (table.concat out))))

(fn maybe-attach-comment [x indent cs]
  (if (and cs (< 0 (length cs)))
      (.. (table.concat (icollect [_ c (ipairs cs)]
                          (tostring c))
                        (.. "\n" (string.rep " " indent))) "\n"
          (string.rep " " indent) x)
      x))

(fn shorthand-pair? [k v]
  (and (= :string (type k)) (fennel.sym? v) (= k (tostring v))))

(fn view-pair [t view inspector indent mt key key-comments]
  (let [val (. t key)
        k (if (shorthand-pair? key val) ":"
              (view key inspector (+ indent 1) true))
        v (view val inspector (+ indent (slength k) 1))]
    (.. (maybe-attach-comment k indent key-comments) " "
        (maybe-attach-comment v indent (?. mt :comments :values val)))))

(fn view-multiline-kv [pair-strs indent last-comments]
  (if (and last-comments (< 0 (length last-comments)))
      (do
        (each [_ c (ipairs last-comments)]
          (table.insert pair-strs (tostring c)))
        (table.insert pair-strs "}")
        (.. "{" (table.concat pair-strs (.. "\n" (string.rep " " indent)))))
      (.. "{" (table.concat pair-strs (.. "\n" (string.rep " " indent))) "}")))

(fn trailing-count [pair-records]
  (accumulate [n 0 _ record (ipairs pair-records)]
    (+ n (length record.trailing))))

(fn pair-end-column [text indent]
  "Column where the last line of a rendered pair ends. Multi-line pair text
already carries its own absolute indentation ; single-line text starts at the
table's content indent."
  (if (text:find "\n")
      (last-line-length text)
      (+ indent (length text))))

(fn align-trailing-comments [pair-records indent]
  "Attach trailing comments to their pair. When several pairs have one, align
them one column after the widest pair in the table."
  (let [count (trailing-count pair-records)
        max-column (if (< 1 count)
                       (accumulate [column 0 _ record (ipairs pair-records)]
                         (if (< 0 (length record.trailing))
                             (math.max column
                                       (pair-end-column record.text indent))
                             column))
                       nil)]
    (each [_ record (ipairs pair-records)]
      (when (< 0 (length record.trailing))
        (let [column (pair-end-column record.text indent)
              spaces (if max-column
                         (math.max 1 (- (+ max-column 1) column))
                         1)]
          (each [i c (ipairs record.trailing)]
            (set record.text (.. record.text
                                 (if (= i 1)
                                     (string.rep " " spaces)
                                     (.. "\n" (string.rep " " indent)))
                                 (tostring c)))))))))

(fn sorter [a b]
  (if (= (type a) (type b))
      (< a b)
      (< (tostring a) (tostring b))))

(fn view-kv [t view inspector indent]
  "Normal fennelview table printing is insufficient for two reasons: it doesn't
know what to do with : foo shorthand notation, and it doesn't emit comments."
  (let [indent (+ indent 1)
        mt (getmetatable t)
        keys (or mt.keys (doto (icollect [k (pairs t)] k)
                           (table.sort sorter)))
        pair-records []
        leading-last []]
    (var prev-line nil)
    (var has-trailing? false)
    (each [_ key (ipairs keys)]
      (let [val (. t key)
            key-comments (or (?. mt :comments :keys key) [])
            leading []
            trailing []]
        (each [_ c (ipairs key-comments)]
          (if (and prev-line (comment-trailing? c prev-line))
              (table.insert trailing c)
              (table.insert leading c)))
        (let [text (view-pair t view inspector indent mt key leading)
              previous (. pair-records (length pair-records))]
          (when (and previous (< 0 (length trailing)))
            (set has-trailing? true)
            (each [_ c (ipairs trailing)]
              (table.insert previous.trailing c)))
          (table.insert pair-records {:text text :trailing []})
          (set prev-line (line val)))))
    (each [_ c (ipairs (or (?. mt :comments :last) []))]
      (if (and (< 0 (length pair-records)) (comment-trailing? c prev-line))
          (do
            (set has-trailing? true)
            (let [last-record (. pair-records (length pair-records))]
              (table.insert last-record.trailing c)))
          (table.insert leading-last c)))
    (let [pair-strs (icollect [_ record (ipairs pair-records)] record.text)
          oneline (.. "{" (table.concat pair-strs " ") "}")]
      (if (or has-trailing? (oneline:match "\n") (?. mt :comments :last 1)
              (< inspector.line-length (+ indent (length oneline))))
          (do
            (align-trailing-comments pair-records indent)
            (view-multiline-kv (icollect [_ record (ipairs pair-records)]
                                 record.text)
                               indent leading-last))
          oneline))))

(fn walk-tree [root f ?custom-iterator]
  "Walks a tree (like the AST), invoking f(node, idx, parent) on each node.
When f returns a truthy value, recursively walks the children."
  (fn walk [iterfn parent idx node]
    (when (f idx node parent)
      (each [k v (iterfn node)]
        (walk iterfn node k v))))

  (walk (or ?custom-iterator pairs) nil nil root)
  root)

(fn set-fennelview-metamethod [_idx form]
  (when (not (scalar? form))
    (when (and (not (fennel.list? form)) (not (fennel.sequence? form)))
      ;; Fennel's parser will always set the metatable, but we could get tables
      ;; from other places.
      (case (getmetatable form)
        mt (set mt.__fennelview view-kv)
        _ (setmetatable form {:__fennelview view-kv})))
    true))

(fn prefer-colon? [s]
  ;; it has to be a legal colon-string, but it shouldn't be *just* punctuation
  (and (s:find "^[-%w?^_!$%&*+./|<=>]+$")
       (not (s:find "^[-?^_!$%&*+./@|<=>%\\]+$"))))

(fn skip-comment? [ast]
  "Recognize the new skip comment and the legacy fnlfmt one."
  (and (fennel.comment? ast)
       (let [text (tostring ast)]
         (or (= text (.. ";; " config.project-name ": skip"))
             (= text ";; fnlfmt: skip")))))

(fn fennelfmt [ast ?settings]
  "Return a formatted representation of ast."
  (let [settings (or ?settings {})
        classifier (classify.build settings)
        previous current-classifier
        _ (set current-classifier classifier)
        {&as list-mt : __fennelview} (getmetatable (fennel.list))
        ;; list's metamethod for fennelview is where the magic happens!
        _ (set list-mt.__fennelview view-list)
        ;; this would be better if we operated on a copy!
        _ (walk-tree ast set-fennelview-metamethod)
        (ok? val) (pcall fennel.view ast
                         {:empty-as-sequence? true
                          :escape-newlines? true
                          :line-length (or settings.line-length 80)
                          :classifier classifier
                          : prefer-colon?})]
    ;; clean up after the metamethod patching
    (set list-mt.__fennelview __fennelview)
    (set current-classifier previous)
    (assert ok? val)
    val))

(fn space-out-forms? [prev-ast ast]
  "Use previous line numbering to determine whether to space out forms."
  (not (and (line prev-ast) (line ast) (= 1 (- (line ast) (line prev-ast))))))

(fn parse-form [value source raw]
  (if (and raw (or (= :string (type value)) (= :number (type value))))
      (setmetatable (doto source
                      (tset :raw raw)
                      (tset :value value)) raw-mt)
      value))

(fn format-file [filename ?options]
  "Read source from a file and return formatted source."
  (let [options (or ?options {})
        settings (or options.settings (config.resolve filename options))
        no-comments (if (not= nil options.no-comments)
                        options.no-comments
                        settings.no-comments)
        (f err) (if (= filename "-")
                    (values io.stdin nil)
                    (io.open filename :r))]
    (when (not f)
      (error (or err (.. "cannot read " filename)) 0))
    (let [original (f:read :*all)
          parser (-> (fennel.stringStream original)
                     (fennel.parser filename
                                    {:comments (not no-comments)
                                     :plugins [{:name "fennelfmt"
                                                :parse-form parse-form
                                                :versions "^1%."}]}))
          out []
          skipped-elements {}]
      (when (not= f io.stdin)
        (f:close))
      (let [previous-source-lines current-source-lines]
        (set current-source-lines (split-lines original))
        (var (skip-next? prev-ast) false)
        (each [ok? ast parser]
          (assert ok? ast)
          (if (and (fennel.comment? ast) prev-ast
                   (= (line ast) (end-line prev-ast)))
              ;; A comment that shared a line with the previous form stays
              ;; attached to it.
              (tset out (length out)
                    (.. (. out (length out)) " " (tostring ast)))
              (and skip-next? ast.bytestart ast.byteend)
              (do
                (table.insert out (original:sub ast.bytestart ast.byteend))
                (tset skipped-elements (length out) true)
                (set skip-next? false))
              (skip-comment? ast)
              (do
                (set skip-next? true)
                (table.insert out "")
                (table.insert out (tostring ast)))
              (do
                (when (and prev-ast (space-out-forms? prev-ast ast))
                  (table.insert out ""))
                (table.insert out (fennelfmt ast settings))
                (set skip-next? false)))
          (set prev-ast ast))
        (set current-source-lines previous-source-lines))
      (table.insert out "")
      (let [formatted (table.concat out "\n")
            formatted (align-comment-runs formatted
                                          (excluded-output-lines out
                                                                 skipped-elements))
            formatted (if (= false settings.trailing-newline?)
                          (formatted:gsub "\n$" "")
                          formatted)]
        (values formatted (not= formatted original) original)))))

{: fennelfmt : format-file :version :0.6.0}
