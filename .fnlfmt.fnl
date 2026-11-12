;; fnlfmt configuration for this repository.
;; Every key is set to its default value so the full surface is visible.
;;
;; :forms replaces the built-in classification table; the entries below are
;; the current built-ins. Use :extra-forms to add to them instead.

{:version 1
 :style :default
 :line-length 80
 :indent 2
 :align-calls? true
 :trailing-newline? true
 :no-comments false
 :forms {:-> :threading
         :->> :threading
         :-?> :threading
         :-?>> :threading
         :accumulate :binding
         :case :match
         :case-try :match
         :collect :binding
         :comment :body
         :do :block
         :doto :body
         :each :binding
         :eval-compiler :block
         :faccumulate :binding
         :fcollect :binding
         :fn :function
         :for :binding
         :icollect :binding
         :if :conditional
         :lambda :function
         :let :binding
         :macro :function
         :match :match
         :match-try :match
         :when :body
         :while :body
         :with-open :binding
         :λ :function}
 :extra-forms {}
 :form-patterns []
 :unknown-form-style :call
 :infer-macros? true}
