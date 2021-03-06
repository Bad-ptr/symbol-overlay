;;; symbol-overlay.el --- Highlight symbols with keymap-enabled overlays

;; Copyright (C) 2017 wolray

;; Author: wolray <wolray@foxmail.com>
;; Version: 3.5
;; URL: https://github.com/wolray/symbol-overlay/
;; Keywords: faces, matching
;; Package-Requires: ((emacs "24.3"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Highlighting symbols with overlays while providing a keymap for various
;; operations about highlighted symbols.  It was originally inspired by the
;; package `highlight-symbol'.  The fundamental difference is that in
;; `symbol-overlay' every symbol is highlighted by the Emacs built-in function
;; `overlay-put' rather than the `font-lock' mechanism used in
;; `highlight-symbol'.

;; Advantages

;; When highlighting symbols in a buffer of regular size and language,
;; `overlay-put' behaves as fast as the traditional highlighting method
;; `font-lock'.  However, for a buffer of major-mode with complicated keywords
;; syntax, like haskell-mode, `font-lock' is quite slow even the buffer is less
;; than 100 lines.  Besides, when counting the number of highlighted
;; occurrences, `highlight-symbol' will call the function `how-many' twice,
;; which could also result in an unpleasant delay in a large buffer.  Those
;; problems don't exist in `symbol-overlay'.

;; When putting overlays on symbols, an auto-activated overlay-inside keymap
;; will enable you to call various useful commands with a single keystroke.

;; Toggle all overlays of symbol at point: `symbol-overlay-put'
;; Jump between locations of symbol at point: `symbol-overlay-jump-next' &
;; `symbol-overlay-jump-prev'
;; Switch to the closest symbol highlighted nearby:
;; `symbol-overlay-switch-forward' & `symbol-overlay-switch-backward'
;; Minor mode for auto-highlighting symbol at point: `symbol-overlay-mode'
;; Remove all highlighted symbols in the buffer: `symbol-overlay-remove-all'
;; Copy symbol at point: `symbol-overlay-save-symbol'
;; Toggle overlays to be showed in buffer or only in scope:
;; `symbol-overlay-toggle-in-scope'
;; Jump back to the position before a recent jump: `symbol-overlay-echo-mark'
;; Jump to the definition of symbol at point: `symbol-overlay-jump-to-definition'
;; Isearch symbol at point literally, without `regexp-quote' the symbol:
;; `symbol-overlay-isearch-literally'
;; Query replace symbol at point: `symbol-overlay-query-replace'
;; Rename symbol at point on all its occurrences: `symbol-overlay-rename'

;; Usage

;; To use `symbol-overlay' in your Emacs, you need only to bind these keys:
;; (require 'symbol-overlay)
;; (global-set-key (kbd "M-i") 'symbol-overlay-put)
;; (global-set-key (kbd "M-n") 'symbol-overlay-switch-forward)
;; (global-set-key (kbd "M-p") 'symbol-overlay-switch-backward)
;; (global-set-key (kbd "<f7>") 'symbol-overlay-mode)
;; (global-set-key (kbd "<f8>") 'symbol-overlay-remove-all)

;; Default key-bindings are defined in `symbol-overlay-map'.
;; You can re-bind the commands to any keys you prefer by simply writing
;; (define-key symbol-overlay-map (kbd "your-prefer-key") 'any-command)

;;; Code:

(require 'thingatpt)
(require 'seq)

(defvar symbol-overlay-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "i") 'symbol-overlay-put)
    (define-key map (kbd "n") 'symbol-overlay-jump-next)
    (define-key map (kbd "p") 'symbol-overlay-jump-prev)
    (define-key map (kbd "w") 'symbol-overlay-save-symbol)
    (define-key map (kbd "t") 'symbol-overlay-toggle-in-scope)
    (define-key map (kbd "e") 'symbol-overlay-echo-mark)
    (define-key map (kbd "d") 'symbol-overlay-jump-to-definition)
    (define-key map (kbd "s") 'symbol-overlay-isearch-literally)
    (define-key map (kbd "q") 'symbol-overlay-query-replace)
    (define-key map (kbd "r") 'symbol-overlay-rename)
    map)
  "Keymap automatically activated inside overlays.
You can re-bind the commands to any keys you prefer.")

(defvar symbol-overlay-keywords-alist)
(make-variable-buffer-local 'symbol-overlay-keywords-alist)

(defvar symbol-overlay-colors '("dodger blue"
				"hot pink"
				"orange"
				"orchid"
				"red"
				"salmon"
				"spring green"
				"turquoise")
  "Colors used for overlays' background.
You can add more colors whatever you like.")

(defun symbol-overlay-get-list (&optional symbol car-or-cdr exclude)
  "Get all highlighted overlays in the buffer.
If SYMBOL is non-nil, get the overlays that belong to it.
CAR-OR-CDR must a symbol whose value is 'car or 'cdr, if not nil.
If EXCLUDE is non-nil, get all overlays excluding those belong to SYMBOL."
  (let ((lists (progn (overlay-recenter (point)) (overlay-lists))))
    (seq-filter
     '(lambda (overlay)
	(let ((value (overlay-get overlay 'symbol)))
	  (and value
	       (or (not symbol)
		   (if (string= value symbol) (not exclude)
		     (and exclude (not (string= value ""))))))))
     (if car-or-cdr (funcall car-or-cdr lists)
       (append (car lists) (cdr lists))))))

(defun symbol-overlay-get-symbol (&optional string noerror)
  "Get the symbol at point.
If STRING is non-nil, `regexp-quote' STRING rather than the symbol.
If NOERROR is non-nil, just return nil when no symbol is found."
  (let ((symbol (or string (thing-at-point 'symbol))))
    (if symbol (concat "\\_<" (regexp-quote symbol) "\\_>")
      (unless noerror (user-error "No symbol at point")))))

(defun symbol-overlay-assoc (symbol)
  "Get SYMBOL's associated list in `symbol-overlay-keywords-alist'."
  (assoc symbol symbol-overlay-keywords-alist))

(defun symbol-overlay-remove (keyword)
  "Delete the KEYWORD list and all its overlays."
  (when keyword
    (mapc 'delete-overlay (symbol-overlay-get-list (car keyword)))
    (setq symbol-overlay-keywords-alist
	  (delq keyword symbol-overlay-keywords-alist))
    (cddr keyword)))

(defvar symbol-overlay-temp-symbol nil
  "Symbol for temporary highlighting.")
(make-variable-buffer-local 'symbol-overlay-temp-symbol)

(defvar symbol-overlay-temp-in-scope nil
  "If non-nil, force to narrow to scope before temporary highlighting.")
(make-variable-buffer-local 'symbol-overlay-temp-in-scope)

(defun symbol-overlay-narrow (scope &optional window)
  "Narrow to a specific region.
Region might be current scope or displayed window or a specific one,
depending on `symbol-overlay-temp-symbol', `symbol-overlay-temp-in-scope',
SCOPE and WINDOW."
  (if (or scope (and symbol-overlay-temp-symbol symbol-overlay-temp-in-scope))
      (let ((pt (point))
	    min max p)
	(save-excursion
	  (save-restriction
	    (narrow-to-defun)
	    (setq min (point-min)
		  max (point-max)
		  p (/= pt (point))))
	  (and p (setq min (progn (backward-paragraph) (point))
		       max (progn (forward-paragraph) (point))))
	  (narrow-to-region min max)))
    (when window
      (let ((lines (round (window-screen-lines)))
	    (pt (point))
	    beg)
	(save-excursion
	  (forward-line (- lines))
	  (setq beg (point))
	  (goto-char pt)
	  (forward-line lines)
	  (narrow-to-region beg (point)))))))

(defvar symbol-overlay-temp-face
  '((:background "gray70")
    (:foreground "gray30"))
  "Face for temporary highlighting.")

(defun symbol-overlay-put-temp-one (symbol bounds)
  "Put overlay on one occurrence of SYMBOL with BOUNDS.
It use `symbol-overlay-temp-face' as face and is only for temporary use."
  (let ((overlay (make-overlay (car bounds) (cdr bounds))))
    (overlay-put overlay 'face symbol-overlay-temp-face)
    (overlay-put overlay 'symbol "")))

(defun symbol-overlay-remove-temp ()
  "Delete all temporary overlays."
  (mapc 'delete-overlay (symbol-overlay-get-list ""))
  (setq symbol-overlay-temp-symbol nil))

(defun symbol-overlay-put-temp-in-window ()
  "Highlight symbol at point when there are more than 2 occurrences.
This only effects symbols in the current displayed window."
  (when symbol-overlay-mode
    (let ((case-fold-search nil)
	  (symbol (symbol-overlay-get-symbol nil t))
	  bounds first p)
      (when (and symbol (not (symbol-overlay-assoc symbol)))
	(symbol-overlay-remove-temp)
	(save-excursion
	  (save-restriction
	    (symbol-overlay-narrow symbol-overlay-temp-in-scope t)
	    (goto-char (point-min))
	    (while (re-search-forward symbol nil t)
	      (setq bounds (cons (match-beginning 0) (match-end 0)))
	      (if (not first) (setq first bounds)
		(symbol-overlay-put-temp-one symbol bounds)
		(or p (setq p t))))
	    (when p
	      (symbol-overlay-put-temp-one symbol first)
	      (setq symbol-overlay-temp-symbol symbol))))))))

(defvar symbol-overlay-timer nil
  "Timer for temporary highlighting.")

(defvar symbol-overlay-idle-time 0.5
  "Idle time after every command and before the temporary highlighting.")

(defun symbol-overlay-update-timer (value)
  "Update `symbol-overlay-timer' with new idle-time VALUE."
  (and symbol-overlay-timer (cancel-timer symbol-overlay-timer))
  (setq symbol-overlay-timer
	(and value (> value 0)
	     (run-with-idle-timer value t 'symbol-overlay-put-temp-in-window))))

(defun symbol-overlay-post-command ()
  "Installed on `post-command-hook'."
  (unless (string= (symbol-overlay-get-symbol nil t) symbol-overlay-temp-symbol)
    (symbol-overlay-remove-temp)))

(define-minor-mode symbol-overlay-mode
  "Minor mode for auto-highlighting symbol at point."
  nil " SO" nil
  (if symbol-overlay-mode
      (progn
	(add-hook 'post-command-hook 'symbol-overlay-post-command nil t)
	(symbol-overlay-update-timer symbol-overlay-idle-time))
    (remove-hook 'post-command-hook 'symbol-overlay-post-command t)
    (symbol-overlay-remove-temp)))

(defun symbol-overlay-put-one (symbol color)
  "Put overlay on current occurrence of SYMBOL after a match.
Use COLOR as the overlay's background color."
  (let ((overlay (make-overlay (match-beginning 0) (match-end 0)))
	(face `((:background ,color)
		(:foreground "black"))))
    (overlay-put overlay 'face face)
    (overlay-put overlay 'keymap symbol-overlay-map)
    (overlay-put overlay 'evaporate t)
    (overlay-put overlay 'symbol symbol)))

(defun symbol-overlay-put-all (symbol &optional scope keyword)
  "Put overlays on all occurrences of SYMBOL in the buffer.
The background color is randomly picked from `symbol-overlay-colors'.
If SCOPE is non-nil, put overlays only on occurrences in scope.
If KEYWORD is non-nil, remove it then use its color on new overlays."
  (let* ((case-fold-search nil)
	 (limit (length symbol-overlay-colors))
	 (color (or (symbol-overlay-remove keyword)
		    (elt symbol-overlay-colors (random limit))))
	 (alist symbol-overlay-keywords-alist)
	 (colors (mapcar 'cddr alist))
	 (pt (point)))
    (if (< (length alist) limit)
	(while (seq-position colors color)
	  (setq color (elt symbol-overlay-colors (random limit))))
      (setq color (symbol-overlay-remove (car (last alist)))))
    (and symbol-overlay-temp-symbol (symbol-overlay-remove-temp))
    (save-excursion
      (save-restriction
	(symbol-overlay-narrow scope)
	(goto-char (point-min))
	(while (re-search-forward symbol nil t)
	  (symbol-overlay-put-one symbol color))))
    (setq keyword `(,symbol ,scope . ,color))
    (push keyword symbol-overlay-keywords-alist)
    keyword))

(defun symbol-overlay-count (keyword &optional show-color)
  "Show the number of KEYWORD's occurrences.
If SHOW-COLOR is non-nil, display the color used by current overlay."
  (when keyword
    (let* ((symbol (car keyword))
	   (before (symbol-overlay-get-list symbol 'car))
	   (after (symbol-overlay-get-list symbol 'cdr))
	   (count (length before)))
      (message (concat (substring symbol 3 -3)
		       ": %d/%d"
		       (and keyword (cadr keyword) " in scope")
		       (and show-color (format " (%s)" (cddr keyword))))
	       (+ count 1)
	       (+ count (length after))))))

;;;###autoload
(defun symbol-overlay-put ()
  "Toggle all overlays of symbol at point."
  (interactive)
  (unless (minibufferp)
    (let* ((symbol (symbol-overlay-get-symbol))
	   (keyword (symbol-overlay-assoc symbol)))
      (if keyword
	  (progn
	    (symbol-overlay-remove keyword)
	    (symbol-overlay-put-temp-in-window))
	(and (looking-at-p "\\_>") (backward-char))
	(symbol-overlay-count (symbol-overlay-put-all symbol) t)))))

;;;###autoload
(defun symbol-overlay-remove-all ()
  "Remove all highlighted symbols in the buffer."
  (interactive)
  (unless (minibufferp)
    (mapc 'delete-overlay (symbol-overlay-get-list))
    (setq symbol-overlay-keywords-alist nil)))

;;;###autoload
(defun symbol-overlay-save-symbol ()
  "Copy symbol at point."
  (interactive)
  (unless (minibufferp)
    (let ((bounds (bounds-of-thing-at-point 'symbol)))
      (kill-ring-save (car bounds) (cdr bounds))
      (message "Current symbol saved"))))

;;;###autoload
(defun symbol-overlay-toggle-in-scope ()
  "Toggle overlays to be showed in buffer or only in scope."
  (interactive)
  (unless (minibufferp)
    (let* ((symbol (symbol-overlay-get-symbol))
	   (keyword (symbol-overlay-assoc symbol))
	   (scope (not (cadr keyword))))
      (symbol-overlay-count (symbol-overlay-put-all symbol scope keyword)))))

(defvar symbol-overlay-mark nil
  "A mark used for jumping back to the point saved befored.")
(make-variable-buffer-local 'symbol-overlay-mark)

;;;###autoload
(defun symbol-overlay-echo-mark ()
  "Jump back to the mark `symbol-overlay-mark'."
  (interactive)
  (or (minibufferp) (not symbol-overlay-mark) (goto-char symbol-overlay-mark)))

(defun symbol-overlay-jump-call (jump-function dir)
  "A general jumping process during which JUMP-FUNCTION is called to jump.
DIR must be 1 or -1."
  (unless (minibufferp)
    (let* ((symbol (symbol-overlay-get-symbol))
	   (keyword (symbol-overlay-assoc symbol)))
      (setq symbol-overlay-mark (point))
      (save-restriction
	(symbol-overlay-narrow (cadr keyword))
	(funcall jump-function symbol dir)
	(if keyword (symbol-overlay-count keyword)
	  (symbol-overlay-mode)
	  (symbol-overlay-put-temp-in-window))))))

(defun symbol-overlay-basic-jump (symbol dir)
  "Jump to SYMBOL's next location in the direction DIR.  DIR must be 1 or -1."
  (let* ((case-fold-search nil)
	 (bounds (bounds-of-thing-at-point 'symbol))
	 (offset (- (point) (if (> dir 0) (cdr bounds) (car bounds))))
	 target)
    (goto-char (- (point) offset))
    (setq target (re-search-forward symbol nil t dir))
    (unless target
      (goto-char (if (> dir 0) (point-min) (point-max)))
      (setq target (re-search-forward symbol nil nil dir)))
    (goto-char (+ target offset))))

;;;###autoload
(defun symbol-overlay-jump-next ()
  "Jump to the next location of symbol at point."
  (interactive)
  (symbol-overlay-jump-call 'symbol-overlay-basic-jump 1))

;;;###autoload
(defun symbol-overlay-jump-prev ()
  "Jump to the previous location of symbol at point."
  (interactive)
  (symbol-overlay-jump-call 'symbol-overlay-basic-jump -1))

(defvar symbol-overlay-definition-function
  '(lambda (symbol) (concat "(?def[a-z-]* " symbol))
  "An one-argument function that returns a regexp.")
(make-variable-buffer-local 'symbol-overlay-definition-function)

;;;###autoload
(defun symbol-overlay-jump-to-definition ()
  "Jump to the definition of symbol at point.
The definition syntax should be defined in a function stored in
`symbol-overlay-definition-function' that returns the definition's regexp
with the input symbol."
  (interactive)
  (symbol-overlay-jump-call
   '(lambda (symbol dir)
      (let ((pt (point)) p)
	(symbol-overlay-basic-jump symbol dir)
	(while (not (or p (save-excursion
			    (beginning-of-line)
			    (skip-chars-forward " \t")
			    (looking-at-p
			     (funcall symbol-overlay-definition-function
				      symbol)))))
	  (symbol-overlay-basic-jump symbol dir)
	  (and (= pt (point)) (setq p t)))))
   1))

(defun symbol-overlay-switch-symbol (dir)
  "Switch to the closest symbol highlighted nearby, in the direction DIR.
DIR must be 1 or -1."
  (unless (minibufferp)
    (let* ((symbol (symbol-overlay-get-symbol nil t))
	   (list (symbol-overlay-get-list symbol (if (> dir 0) 'cdr 'car) t)))
      (or list
	  (user-error (concat "No more "
			      (if (> dir 0) "forward" "backward")
			      " symbols")))
      (setq symbol-overlay-mark (point))
      (goto-char (overlay-start (car list)))
      (symbol-overlay-count
       (symbol-overlay-assoc (symbol-overlay-get-symbol))))))

;;;###autoload
(defun symbol-overlay-switch-forward ()
  "Switch forward to another symbol."
  (interactive)
  (symbol-overlay-switch-symbol 1))

;;;###autoload
(defun symbol-overlay-switch-backward ()
  "Switch backward to another symbol."
  (interactive)
  (symbol-overlay-switch-symbol -1))

;;;###autoload
(defun symbol-overlay-isearch-literally ()
  "Isearch symbol at point literally, without `regexp-quote' the symbol."
  (interactive)
  (unless (minibufferp)
    (let ((symbol (symbol-overlay-get-symbol)))
      (beginning-of-thing 'symbol)
      (isearch-forward nil t)
      (isearch-yank-string (substring symbol 3 -3)))))

;;;###autoload
(defun symbol-overlay-query-replace ()
  "Query replace symbol at point."
  (interactive)
  (unless (minibufferp)
    (let* ((case-fold-search nil)
	   (symbol (symbol-overlay-get-symbol))
	   (keyword (symbol-overlay-assoc symbol))
	   (scope (cadr keyword))
	   txt defaults new)
      (and scope (user-error "Query-replace invalid in scope"))
      (beginning-of-thing 'symbol)
      (setq symbol-overlay-mark (point)
	    txt (read-string "Replacement: ")
	    new (symbol-overlay-get-symbol txt)
	    defaults (cons symbol txt))
      (unless (string= new symbol)
	(symbol-overlay-remove (symbol-overlay-assoc new))
	(setq keyword (symbol-overlay-put-all new scope keyword))
	(query-replace-regexp symbol txt)
	(setq query-replace-defaults
	      (if (< emacs-major-version 25) `,defaults `(,defaults))))
      (when (string= new (symbol-overlay-get-symbol nil t))
	(beginning-of-thing 'symbol)
	(symbol-overlay-count keyword)))))

;;;###autoload
(defun symbol-overlay-rename ()
  "Rename symbol at point on all its occurrences."
  (interactive)
  (unless (minibufferp)
    (let* ((case-fold-search nil)
	   (symbol (symbol-overlay-get-symbol))
	   (keyword (symbol-overlay-assoc symbol))
	   (scope (cadr keyword))
	   txt new)
      (beginning-of-thing 'symbol)
      (setq symbol-overlay-mark (point)
	    txt (read-string (concat "Rename" (and scope " in scope") ": "))
	    new (symbol-overlay-get-symbol txt))
      (unless (string= new symbol)
	(symbol-overlay-remove (symbol-overlay-assoc new))
	(save-excursion
	  (save-restriction
	    (symbol-overlay-narrow scope)
	    (goto-char (point-min))
	    (let ((inhibit-modification-hooks t))
	      (while (re-search-forward symbol nil t) (replace-match txt t)))))
	(setq keyword (symbol-overlay-put-all new scope keyword)))
      (when (string= new (symbol-overlay-get-symbol nil t))
	(symbol-overlay-count keyword)))))

(defun symbol-overlay-refresh (beg end len)
  "Refresh overlays.  Installed on `after-change-functions'.
BEG, END and LEN are the beginning, end and length of changed text."
  (unless (or (minibufferp) (not symbol-overlay-keywords-alist))
    (let ((case-fold-search nil)
	  (re "\\(\\sw\\|\\s_\\)+"))
      (save-excursion
	(save-match-data
	  (goto-char end)
	  (and (looking-at-p re)
	       (setq end (re-search-forward "\\_>")))
	  (goto-char beg)
	  (and (not (looking-at-p "\\_<"))
	       (looking-at-p (concat "\\(" re "\\|\\_>\\)"))
	       (setq beg (re-search-backward "\\_<")))
	  (mapc #'(lambda (overlay)
		    (and (overlay-get overlay 'symbol)
			 (delete-overlay overlay)))
		(overlays-in beg end))
	  (mapc #'(lambda (keyword)
		    (let ((symbol (car keyword)))
		      (goto-char beg)
		      (while (re-search-forward symbol end t)
			(symbol-overlay-put-one symbol (cddr keyword)))))
		symbol-overlay-keywords-alist))))))

(add-hook 'after-change-functions 'symbol-overlay-refresh)

(provide 'symbol-overlay)

;;; symbol-overlay.el ends here
