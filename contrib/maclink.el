;;; maclink.el --- Optional Emacs sugar for maclink -*- lexical-binding: t; -*-

;; This is entirely optional. `maclink://open/<uuid>' links already open
;; with zero configuration: org-mode falls through to `browse-url' for
;; unrecognized schemes, and `browse-url-default-macosx-browser' shells out
;; to `/usr/bin/open', which Launch Services routes straight to maclink.
;; See README.md and SPEC.md §10 for the full story.
;;
;; What this file adds on top of that baseline:
;;   - `maclink-insert-from-clipboard': paste the link just captured by the
;;     hotkey as a proper org link. Needs no CLI, just the clipboard.
;;   - `maclink-insert-latest': same, but pulls the most recent capture from
;;     the database instead of the clipboard (spec §10.3).
;;   - A real `maclink' org link type (spec §10.4), purely for nicer
;;     display/completion/export in org buffers. NOT required for opening.
;;
;; `maclink-insert-latest' and the org link type's completion both shell out
;; to the `maclink' CLI (Sources/maclink-cli), which reads the database
;; read-only. Install it first with Scripts/install-cli.sh, which puts it at
;; ~/.local/bin/maclink -- make sure that's on Emacs's `exec-path'/`PATH'.

(require 'org)

(defun maclink--cli (&rest args)
  "Run the maclink CLI with ARGS, returning trimmed stdout.
Signals a `user-error' with the CLI's own message on failure, e.g. when it
isn't installed or the database has no links yet."
  (with-temp-buffer
    (let ((status (apply #'call-process "maclink" nil t nil args)))
      (unless (zerop status)
        (user-error "%s" (string-trim (buffer-string)))))
    (string-trim (buffer-string))))

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

;;;###autoload
(defun maclink-insert-latest ()
  "Insert the most recently captured maclink as an org link at point.
Bind this to something like \\[maclink-insert-latest], e.g. `C-c m' in
`org-mode-map'."
  (interactive)
  (insert (maclink--cli "latest" "--org")))

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
  "Completing-read over saved links via the maclink CLI."
  (let* ((rows (split-string (maclink--cli "search" "" "--limit" "200") "\n" t))
         (choice (completing-read "maclink: " rows)))
    (concat "maclink:" (car (split-string choice "\t")))))

(org-link-set-parameters "maclink"
  :follow   #'maclink-org-follow
  :export   #'maclink-org-export
  :complete #'maclink-org-complete
  :face     '(:foreground "DarkOrange" :underline t))

(provide 'maclink)
;;; maclink.el ends here
