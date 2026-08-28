;;; maclink.el --- Optional Emacs sugar for maclink -*- lexical-binding: t; -*-

;; This is entirely optional. `maclink://open/<uuid>` links already open
;; with zero configuration: org-mode falls through to `browse-url' for
;; unrecognized schemes, and `browse-url-default-macosx-browser' shells out
;; to `/usr/bin/open', which Launch Services routes straight to maclink.
;; See README.md and SPEC.md §10 for the full story.
;;
;; What this file adds on top of that baseline:
;;   - `maclink-insert-from-clipboard': paste the link just captured by the
;;     hotkey as a proper org link, without needing a maclink CLI.
;;   - A real `maclink' org link type (spec §10.4), purely for nicer
;;     display/completion/export in org buffers. NOT required for opening.
;;     Completion queries the database directly via the `sqlite3' CLI
;;     (present on every Mac), since maclink deliberately keeps its
;;     database plain and queryable rather than shipping a separate tool
;;     just for this.

(require 'org)

(defconst maclink-db-path
  (expand-file-name "~/Library/Application Support/com.tilak.maclink/maclink.sqlite")
  "Path to maclink's SQLite database. Read-only access only. Never write
here from Emacs; the running app owns writes, and this file may be opened
concurrently via WAL mode, which tolerates concurrent readers just fine.")

;;;###autoload
(defun maclink-insert-from-clipboard ()
  "Insert the maclink:// URL currently on the macOS pasteboard as an org link.
Bind this to something like \\[maclink-insert-from-clipboard] right after
pressing maclink's capture hotkey."
  (interactive)
  (let ((s (string-trim (shell-command-to-string "pbpaste"))))
    (cond
     ((string-match "\\`\\[\\[maclink://" s) (insert s)) ; already org-formatted
     ((string-match "\\`maclink://" s)
      (insert (format "[[%s][%s]]" s (read-string "Description: "))))
     (t (user-error "Clipboard does not contain a maclink URL")))))

(defun maclink--sqlite (sql)
  "Run SQL against maclink's database read-only, returning trimmed output."
  (unless (file-exists-p maclink-db-path)
    (user-error "maclink database not found at %s" maclink-db-path))
  (string-trim
   (shell-command-to-string
    (format "sqlite3 -readonly -separator '\t' %s %s"
            (shell-quote-argument maclink-db-path)
            (shell-quote-argument sql)))))

(defun maclink-org-follow (path _arg)
  "Open a `maclink:PATH' org link. PATH shows up two different ways
depending on how the link was written: a link pasted straight from the
clipboard (`[[maclink://open/<uuid>][title]]') keeps its leading \"//\"
since org strips only the `maclink:' type prefix; a link built by
`maclink-org-complete' below (`[[maclink:open/<uuid>]]') has none. Both
must resolve to the same well-formed `maclink://...' URL for `open'."
  (let ((normalized (if (string-prefix-p "//" path) path (concat "//" path))))
    (start-process "maclink" nil "open" (concat "maclink:" normalized))))

(defun maclink-org-export (path desc _backend)
  (or desc (concat "maclink://" (string-remove-prefix "//" path))))

(defun maclink-org-complete ()
  "Completing-read over saved links, queried directly from the database."
  (let* ((rows (split-string
                (maclink--sqlite
                 "SELECT id, title FROM links WHERE archived = 0 ORDER BY created_at DESC LIMIT 200;")
                "\n" t))
         (choice (completing-read "maclink: " rows)))
    (concat "maclink:open/" (downcase (car (split-string choice "\t"))))))

(org-link-set-parameters "maclink"
  :follow   #'maclink-org-follow
  :export   #'maclink-org-export
  :complete #'maclink-org-complete
  :face     '(:foreground "DarkOrange" :underline t))

(provide 'maclink)
;;; maclink.el ends here
