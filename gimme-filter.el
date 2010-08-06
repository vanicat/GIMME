(defvar gimme-filter-header "GIMME - Filter View")
(defvar gimme-new-collection-name "Untitled")
(defvar gimme-filter-mode-functions
  '(gimme-insert-song gimme-set-title message
                      gimme-filter-set-current-col
                      gimme-update-playtime))

(defun gimme-filter ()
  (interactive)
  (gimme-new-session)
  (get-buffer-create gimme-buffer-name)
  (setq gimme-current-mode 'filter)
  (with-current-buffer gimme-buffer-name
    (unlocking-buffer
     (gimme-filter-mode)
     (clipboard-kill-region 1 (point-max))
     (gimme-set-title gimme-filter-header)
     (save-excursion
       (gimme-send-message "(pcol %s %s)\n" (gimme-tree-current-ref) gimme-session)))
    (switch-to-buffer (get-buffer gimme-buffer-name)))) ;; FIXME: Quite redundant and ugly

(defun gimme-child-col ()
  (interactive)
  (let* ((parent (gimme-tree-current-ref))
         (name (getf (gimme-tree-current-data) 'name))
         (name (read-from-minibuffer (format "%s > " name)))
         (message (format "(subcol %s \"%s\")\n" parent name)))
    (setq gimme-new-collection-name (format "Untitled (%s)" name))
    (gimme-send-message message)))

(defun gimme-parent-col ()
  (interactive)
  (if (listp gimme-current)
      (setq gimme-current (butlast gimme-current))
    (gimme-filter)))

(defun gimme-filter-append-focused ()
  (interactive)
  (gimme-send-message "(add %s)\n" (get-text-property (point) 'id)))

(defun gimme-filter-play-focused ()
  (interactive)
  (gimme-send-message "(addplay %s)\n" (get-text-property (point) 'id)))

(defun gimme-filter-append-collection ()
  (interactive)
  (loop for x = (point-min) then (next-property-change x) while x
        collecting (gimme-send-message "(add %s)\n" (get-text-property x 'id))
        finally (message "Songs added!")))

(defun gimme-filter-same ()
  "Creates a subcollection matching some this song's criterium"
  (interactive)
  (let* ((parent (gimme-tree-current-ref))
         (name (completing-read
                "Filter? "
                (mapcar (lambda (n) (format "%s:'%s'" (car n) (cdr n)))
                        (remove-if (lambda (m) (member (car m)
                                                  '(id duration font-lock-face)))
                                   (plist-to-alist (text-properties-at (point)))))))
         (message (format "(subcol %s \"%s\")\n" parent name)))
    (gimme-send-message message)))

(defvar gimme-filter-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "!") 'gimme-filter)
    (define-key map (kbd "@") 'gimme-tree)
    (define-key map (kbd "#") 'gimme-playlist)
    (define-key map (kbd "q") (lambda () (interactive) (kill-buffer gimme-buffer-name)))
    (define-key map (kbd "SPC") 'gimme-toggle)
    (define-key map (kbd "j") 'next-line)
    (define-key map (kbd "k") 'previous-line)
    (define-key map (kbd "J") 'gimme-next)
    (define-key map (kbd "K") 'gimme-prev)
    (define-key map (kbd "TAB") 'gimme-toggle-view)
    (define-key map (kbd "=") 'gimme-inc_vol) ;; FIXME: Better names, please!
    (define-key map (kbd "+") 'gimme-inc_vol)
    (define-key map (kbd "-") 'gimme-dec_vol)

    (define-key map (kbd "<") 'gimme-parent-col)
    (define-key map (kbd ">") 'gimme-child-col)
    (define-key map (kbd "a") 'gimme-filter-append-focused)
    (define-key map (kbd "RET") 'gimme-filter-play-focused)
    (define-key map (kbd "A") 'gimme-filter-append-collection)
    (define-key map (kbd "f") 'gimme-filter-same)
    map))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Called by the ruby part ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun gimme-filter-set-current-col (ref)
  (setq gimme-current
        (append gimme-current
                `(,(gimme-tree-add-child
                    `(name ,gimme-new-collection-name ref ,ref)
                    gimme-current))))
  (gimme-filter))


(provide 'gimme-filter)
