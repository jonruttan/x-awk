; # x-awk -- POSIX awk on x-lang
;
; ## awk/split.x -- records and fields, cut by the platform's lexer
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Input is cut twice: a chunk into records at RS, and a record into fields at
; FS.  Both were byte walks in x, at 40 to 80 us a byte -- more than all the
; rest a record costs -- and both are the shape x/reader/lexer reads as native
; code: a run of bytes that are not the separator, and the separator.  A
; lexer is made for each separator byte seen and kept, since FS and RS change
; rarely, and one serves both cuts: a record at RS and a field at FS are the
; same two rules.  The blank regime (FS " ") is a lexer of its own, runs of
; non-blanks with the blanks dropped.
;
; The rules leave two things to the walk over the tokens: an EMPTY piece
; between two separators, which no run rule reads, and whether a separator
; closed the text's last piece -- a record reader has to know its last record
; is partial.  The end text appended to every read is the separator byte
; itself: it closes a run, and alone at the end it is no token.

; (BYTE . LEXER) for every separator byte seen; the blank lexer apart
(def %awk-sep-lexers ())
(def %awk-blank-lexer ())

; every byte but B, high bytes either way the engine hands them over
(def %awk-class-but
  (fn (_ b)
    (list (pair 0 (- b 1)) (pair (+ b 1) 255) (pair -128 -1))))

(def %awk-nonblank
  (list (pair 0 8) (pair 11 31) (pair 33 255) (pair -128 -1)))

; HOT (once a record and once a field split): module-level helpers, no
; inner def -- a def in a called body binds globally and grows the env.
(def %awk-sep-lexer-find
  (fn (self b l)
    (if (null? l) ()
      (if (= (first (first l)) b) (rest (first l)) (self b (rest l))))))

(def %awk-sep-lexer
  (fn (_ b)
    (let ((hit (%awk-sep-lexer-find b %awk-sep-lexers)))
      (if (null? hit)
        (let ((sep (list->string (list (integer->char b)))))
          (let ((l (lexer-make
                     (list (lexer-table (lit sep) (list sep))
                           (lexer-run (lit run) (%awk-class-but b) (%awk-class-but b)))
                     sep)))
            (set! %awk-sep-lexers (pair (pair b l) %awk-sep-lexers))
            l))
        hit))))

(def %awk-blank-lexer!
  (fn (_)
    (if (null? %awk-blank-lexer)
      (set! %awk-blank-lexer
        (lexer-make
          (list (lexer-skip " \t\n")
                (lexer-run (lit run) %awk-nonblank %awk-nonblank))
          " "))
      ())
    %awk-blank-lexer))

; The pieces of a text between its separators, from the tokens: (PIECES .
; CLOSED?), CLOSED? when a separator ended the last one.  A run's text is
; never empty, so nil pending means none, and a separator with none pending
; is an empty piece.
(def %awk-pieces-go
  (fn (self ts pending acc)
    (if (null? ts)
      (if (null? pending)
        (pair (reverse acc) #t)
        (pair (reverse (pair pending acc)) #f))
      (if (eq? (first (first ts)) (lit sep))
        (self (rest ts) () (pair (if (null? pending) "" pending) acc))
        (self (rest ts) (first (rest (first ts))) acc)))))

(def %awk-pieces
  (fn (_ ts) (%awk-pieces-go ts () ())))

; the texts of a run of tokens that has no separators
(def %awk-run-texts
  (fn (self ts acc)
    (if (null? ts) (reverse acc)
      (self (rest ts) (pair (first (rest (first ts))) acc)))))

; --- fields ------------------------------------------------------------------

; FS " ": runs of non-blanks, leading and trailing blanks dropped
(def %awk-split-blanks
  (fn (_ s)
    (if (= (byte-len s) 0) ()
      (%awk-run-texts (lexer-read (%awk-blank-lexer!) s) ()))))

; a one-byte separator: a separator at the end opens a trailing empty field,
; as "a," has two fields
(def %awk-split-char
  (fn (_ s b)
    (if (= (byte-len s) 0) ()
      (let ((cut (%awk-pieces (lexer-read (%awk-sep-lexer b) s))))
        (if (rest cut) (append (first cut) (list "")) (first cut))))))

; --- records -----------------------------------------------------------------
;
; A reader (eval.x) keeps the bytes read and not yet consumed; the records in
; them are cut all at once, into a queue the reader pops, and a last piece no
; separator closed stays as the bytes for the next fill to extend.  The queue
; remembers the byte it was cut at: RS applies from the next record, so a
; queue cut at another byte is put back as text and cut again.

; (RECORDS . BUTLAST) -> the pieces but the last, and the last
(def %awk-split-last
  (fn (self ps acc)
    (if (null? (rest ps))
      (pair (reverse acc) (first ps))
      (self (rest ps) (pair (first ps) acc)))))

; the records of TEXT cut at B: (QUEUE . CARRY), CARRY the open last piece
; or "" when a separator closed the text
(def %awk-cut-records
  (fn (_ text b)
    (let ((cut (%awk-pieces (lexer-read (%awk-sep-lexer b) text))))
      (if (rest cut)
        (pair (first cut) "")
        (let ((sl (%awk-split-last (first cut) ())))
          (pair (first sl) (rest sl)))))))

; the queued records put back as text, each closed by the separator they
; were cut at, ahead of TEXT: the last record goes on first
(def %awk-requeue-go
  (fn (self recs sep text)
    (if (null? recs) text
      (self (rest recs) sep
        (string-append (first recs) (string-append sep text))))))
(def %awk-requeue-text
  (fn (_ recs sep text) (%awk-requeue-go (reverse recs) sep text)))
