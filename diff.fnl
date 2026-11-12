;; diff.fnl --- minimal unified diff for fennelfmt --diff
;;
;; This is deliberately small: it uses a greedy nearest-line match instead of
;; a full Myers implementation. The output is a valid unified diff with three
;; lines of context; it may merge changes that a smarter algorithm would
;; split, but it has no external dependencies and is fast enough for source
;; files.

(local context 3)
(local lookahead 20)

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

(fn nearest-match [a b i j n m]
  "Find the nearest pair of offsets (d e) such that a[i+d] == b[j+e].
Offsets are allowed to be zero, but not both."
  (var best nil)
  (for [d 0 lookahead]
    (for [e 0 lookahead]
      (when (and (not (and (= d 0) (= e 0))) (<= (+ i d) n) (<= (+ j e) m)
                 (= (. a (+ i d)) (. b (+ j e)))
                 (or (not best) (< (+ d e) (+ (. best :d) (. best :e)))))
        (set best {:d d :e e}))))
  best)

(fn build-edits [a b]
  (let [n (length a)
        m (length b)
        edits []]
    (var i 1)
    (var j 1)

    (fn add [op old-line new-line text]
      (table.insert edits {:op op :old old-line :new new-line :text text}))

    (while (or (<= i n) (<= j m))
      (if (and (<= i n) (<= j m) (= (. a i) (. b j)))
          (do
            (add :equal i j (. a i))
            (set i (+ i 1))
            (set j (+ j 1)))
          (let [found (nearest-match a b i j n m)]
            (if found
                (let [d (. found :d)
                      e (. found :e)]
                  (for [k 0 (- d 1)]
                    (add :delete (+ i k) j (. a (+ i k))))
                  (for [k 0 (- e 1)]
                    (add :insert (+ i d) (+ j k) (. b (+ j k))))
                  (set i (+ i d))
                  (set j (+ j e)))
                (if (<= i n)
                    (do
                      (add :delete i j (. a i))
                      (set i (+ i 1)))
                    (do
                      (add :insert i j (. b j))
                      (set j (+ j 1))))))))
    edits))

(fn changed-indices [edits]
  (icollect [idx edit (ipairs edits)]
    (when (not= :equal (. edit :op))
      idx)))

(fn hunk-ranges [changed]
  (let [ranges []]
    (var start nil)
    (var last nil)
    (each [_ idx (ipairs changed)]
      (if (not start) (set start idx)
          (< (* 2 context) (- idx last 1)) (do
                                             (table.insert ranges [start last])
                                             (set start idx)))
      (set last idx))
    (when start
      (table.insert ranges [start last]))
    ranges))

(fn hunk-header [edits start stop]
  (var old-start nil)
  (var new-start nil)
  (var old-count 0)
  (var new-count 0)
  (for [i start stop]
    (let [edit (. edits i)
          op (. edit :op)]
      (when (not= op :insert)
        (when (not old-start)
          (set old-start (. edit :old)))
        (set old-count (+ old-count 1)))
      (when (not= op :delete)
        (when (not new-start)
          (set new-start (. edit :new)))
        (set new-count (+ new-count 1)))))
  (when (not old-start)
    (set old-start (. (. edits start) :old)))
  (when (not new-start)
    (set new-start (. (. edits start) :new)))
  (when (= 0 old-count)
    (set old-start (math.max 0 (- old-start 1))))
  (when (= 0 new-count)
    (set new-start (math.max 0 (- new-start 1))))
  (string.format "@@ -%d,%d +%d,%d @@\n" old-start old-count new-start
                 new-count))

(fn label [prefix name]
  (if (= "/" (string.sub name 1 1))
      (.. prefix name)
      (.. prefix "/" name)))

(fn render [edits name]
  (let [changed (changed-indices edits)
        out []]
    (if (= 0 (length changed))
        ""
        (do
          (table.insert out (.. "--- " (label "a" name) "\n"))
          (table.insert out (.. "+++ " (label "b" name) "\n"))
          (each [_ range (ipairs (hunk-ranges changed))]
            (let [start (math.max 1 (- (. range 1) context))
                  stop (math.min (length edits) (+ (. range 2) context))]
              (table.insert out (hunk-header edits start stop))
              (for [i start stop]
                (let [edit (. edits i)
                      op (. edit :op)
                      prefix (case op
                               :equal " "
                               :delete "-"
                               :insert "+")]
                  (table.insert out (.. prefix (. edit :text) "\n"))))))
          (table.concat out "")))))

(fn unified [old new ?name]
  "Return a unified diff between two strings, or an empty string."
  (if (= old new)
      ""
      (render (build-edits (split-lines old) (split-lines new))
              (or ?name :file))))

{: unified : split-lines}
