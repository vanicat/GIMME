;;; gimme.el --- GIMME Interesting Music on My Emacs

;; Author: Konrad Scorciapino <scorciapino@gmail.com>
;; Keywords: XMMS2, mp3

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary

;; GIMME (GIMME Interesting Music on My Emacs) is an XMMS2 client
;; originally developed for Google's Summer of Code. Kudos to them
;; and to DraX for the Support.

;; GIMME works by using collections as search results, and its multiple
;; views allows you to do that in multiple ways. As of GIMME 1.0, you
;; can search and narrow searching using filter-view and better visualize
;; it using tree-view.

;;; Code

(defvar gimme-process nil
  "Reference to the ruby process")
(defvar gimme-executable "gimme.rb"
  "The name of the ruby file")
(defvar gimme-fullpath (expand-file-name
                        (concat
                         (file-name-directory (or load-file-name buffer-file-name))
                         gimme-executable))
  "The fullname of the ruby file")
(defvar gimme-current-mode 'playlist
  "In which mode GIMME current is")
(defvar gimme-buffer-name "GIMME"
  "GIMME's buffer name")
(defvar gimme-session 0
  "Number used to identify the session")
(defvar gimme-filter-remainder ""
  "Variable used to hold incomplete sexps received from the ruby process")
(defvar gimme-debug 0
  "To debug.
  0: Do nothing extra
  1: Prints the functions being called by the ruby process
  2: Print the whole sexps
  3: Print the whole sexps and do not evaluate them")
(defvar gimme-playtime nil
  "Variable used to hold the current track's duration and playtime")
(defvar gimme-current nil
  "The current collection. Can be a string or an idlist")
(defvar gimme-trees nil
  "Collections not saved on the core")

(defvar gimme-tree-header "GIMME - Tree View" "Initial header")
(defvar gimme-playlist-header "GIMME - Playlist view" "Initial header")
(defvar gimme-filter-header "GIMME" "Initial header")

(defvar gimme-tree-mode-functions
  '(message gimme-update-playtime gimme-tree-colls gimme-coll-changed)
  "Functions that can be run when the current mode is gimme-tree")
(defvar gimme-filter-mode-functions
  '(gimme-insert-song gimme-set-title message gimme-filter-set-current-col gimme-update-playtime)
  "Functions that can be run when the current mode is gimme-filter")
(defvar gimme-playlist-mode-functions
  '(gimme-set-playing gimme-update-model gimme-insert-song gimme-set-title message gimme-update-tags gimme-update-playtime)
  "Functions that can be run when the current mode is gimme-playlist")


;;;;;;;;;;;;;;;
;; Functions ;;
;;;;;;;;;;;;;;;

(defun gimme-extract-needed-tags ()
  "Informs the ruby client of all %variables required by the config file"
  (let* ((l (flatten gimme-playlist-formats))
         (l (remove-if-not (lambda (n) (and (symbolp n)
                                       (string-match "^%" (format "%s" n)))) l))
         (l (mapcar (lambda (n) (substring (format "%s" n) 1))
                    (remove-duplicates l))))
    l))

(defun eval-all-sexps (s)
  "Evaluates all sexps from the string. As it will probably encounter a broken sexp, a variable is used to store the remainder to be used in future calls"
  (let ((s (concat gimme-filter-remainder s)))
    (setq gimme-filter-remainder
          (loop for x = (ignore-errors (read-from-string s))
                then (ignore-errors (read-from-string (substring s position)))
                while x
                summing (or (cdr x) 0) into position
                doing (let* ((s (car x))
                             (f (caar x))
                             (ok (member f (case gimme-current-mode
                                             (tree  gimme-tree-mode-functions)
                                             (playlist gimme-playlist-mode-functions)
                                             (filter   gimme-filter-mode-functions)))))
                        (when (> gimme-debug 0)
                          (message (format "GIMME (%s): %s" (if ok "ACK" "NAK") (if (>= gimme-debug 2) f s))))
                        (when (and ok (> 3 gimme-debug)) (eval (car x))))
                finally (return (substring s position))))))

(defun gimme-update-model (plist)
  "Called by the playlist_changed broadcast"
  ;; FIXME: Not seriouly implemented: Move
  (case (getf plist 'type)
    ('add    (progn (run-hook-with-args 'gimme-broadcast-pl-add-hook plist)
                    (gimme-insert-song gimme-session plist t)
                    (message "Song added!")))
    ('insert (progn (run-hook-with-args 'gimme-broadcast-pl-insert-hook plist)
                    (gimme-insert-song gimme-session plist nil)
                    (message "Song added!")))
    ('remove (progn (run-hook-with-args 'gimme-broadcast-pl-remove-hook plist)
                    (setq gimme-last-del (getf plist 'pos))
                    (when (get-buffer gimme-buffer-name)
                      (with-current-buffer gimme-buffer-name
                        (unlocking-buffer
                         (let* ((beg (text-property-any (point-min) (point-max) 'pos
                                                        (getf plist 'pos)))
                                (end (or (next-property-change (or beg (point-min)))
                                         (point-max))))
                           (when (and beg end)
                             (clipboard-kill-region beg end)
                             (gimme-update-pos #'1- (point) (point-max)))))))))
    ('move    (progn (run-hook-with-args 'gimme-broadcast-pl-move-hook plist)
                     (gimme-playlist)
                     (message "Playlist updated! (moving element)")))
    ('shuffle (progn (run-hook-with-args 'gimme-broadcast-pl-shuffle-hook plist)
                     (gimme-playlist)
                     (message "Playlist shuffled!")))
    ('clear   (progn (run-hook-with-args 'gimme-broadcast-pl-clear-hook plist)
                     (gimme-playlist)
                     (message "Playlist cleared!")))
    ('sort    (progn (run-hook-with-args 'gimme-broadcast-pl-sort-hook plist)
                     (gimme-playlist)
                     (message "Playlist updated! (sorting list)")))
    ('update  (progn (run-hook-with-args 'gimme-broadcast-pl-update-hook plist)
                     (gimme-playlist)
                     (message "Playlist updated! (updating list)")))))




(defun gimme-update-playtime (time max)
  "Updates the playtime in the gimme-playtime variable"
  (setq gimme-playtime `((time . ,time) (max . ,max))))

(defmacro gimme-on-buffer (name &rest body)
  "FIXME: Gimme v2"
  `(with-current-buffer (get-buffer-create ,name)
     (unlocking-buffer (save-excursion ,@body))))

(defun gimme-init ()
  "Creates the buffer and manages the processes"
  (dolist (proc (remove-if-not (lambda (el) (string-match "GIMME" el))
                               (mapcar #'process-name (process-list))))
    (kill-process proc))
  (setq gimme-process
        (start-process-shell-command
         gimme-buffer-name nil
         (format "ruby %s" gimme-fullpath )))
  (set-process-filter gimme-process (lambda (a b) (eval-all-sexps b))))

(defun gimme-send-message (&rest args)
  "Formats the arguments using (format) then sends the resulting string to the process."
  (let ((message (apply #'format args)))
    (when (> gimme-debug 0) (message message))
    (process-send-string gimme-process message)))

(defmacro gimme-generate-commands (&rest args)
  "Generates commands that don't require arguments"
  `(mapcar 'eval
           ',(mapcar (lambda (f)
                       `(fset ',(read (format "gimme-%s" f))
                              (lambda () (interactive)
                                (process-send-string gimme-process
                                                     ,(format "%s\n" (list f))))))
                     args)))


(defun gimme-string (plist)
  "Receives a song represented as a plist and binds each key as %key to be used by the formatting functions at gimme-playlist-formats"
  (eval `(let ((plist ',plist)
               ,@(mapcar (lambda (n) (list (intern (format "%%%s" (car n)))
                                      (if (and (symbolp (cdr n)) (not (null (cdr n))))
                                          (list 'quote (cdr n)) (cdr n))))
                         (plist-to-alist plist)))
           (eval (car gimme-playlist-formats)))))


(defun gimme-set-title (title)
  "Changes the header of a buffer"
  (setq gimme-playlist-header title)
  (setq header-line-format
        '(:eval (substring (decode-coding-string gimme-playlist-header 'utf-8)
                           (min (length gimme-playlist-header)
                                (window-hscroll))))))


(defun gimme-toggle-view ()
  "Cycle through the views defined in gimme-config"
  (interactive)
  (setq gimme-playlist-formats
        (append (cdr gimme-playlist-formats)
                (list (car gimme-playlist-formats))))
  (gimme-on-buffer
   (current-buffer)
   
   (comment loop for bounds in (get-bounds-where (lambda (n) t)) and offset = 0
            summing (- (let ((string (gimme-string (plist-put (text-properties-at (car bounds))
                                                              'font-lock-face nil))))
                         (kill-region (+ offset (car bounds)) (+ offset (cadr bounds)))
                         (goto-char (+ offset (car bounds)))
                         (insert string) (length string))
                       (- (cadr bounds) (car bounds)) 1)
            into offset)))

(defun gimme-toggle-view ()
  "Cycle through the views defined in gimme-config"
  (interactive)
  (setq gimme-playlist-formats
        (append (cdr gimme-playlist-formats)
                (list (car gimme-playlist-formats))))
  (gimme-on-buffer
   (current-buffer)
   (let* ((pos (point)) (line (line-number-at-pos)) 
	  (data (range-to-plists (point-min) (point-max)))
	  (data (mapcar (lambda (n) (gimme-string (plist-put n 'font-lock-face nil))) data))
	  (len (length data)))
     (progn ;; Silly but required so that the cursor won't change its
	    ;; position after killing text
       (goto-char (point-min))
       (loop for n from 0 upto (- line 2) doing (insert (nth n data)))
       (move-beginning-of-line 1) (kill-line (- line 2))
       (kill-region (point) (point-max))
       (loop for n from (- line 1) upto (1- len) doing (insert (nth n data)))))))

(defun gimme ()
  "The XMMS2 interface we all love"
  (interactive)
  (setq gimme-filter-remainder "")
  (gimme-init)
  (gimme-send-message (format "(set_atribs %s)\n" (gimme-extract-needed-tags)))
  (gimme-playlist))

;;;;;;;;;;
;; Init ;;
;;;;;;;;;;

(gimme-generate-commands clear shuffle play pause next prev stop toggle current)
(require 'gimme-utils)
(require 'gimme-playlist)
(require 'gimme-tree)
(require 'gimme-filter)
(require 'gimme-status-mode)
(require 'gimme-custom)
(require 'gimme-etc)
(provide 'gimme)

;;; gimme.el ends here
