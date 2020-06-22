;;; org-roam-dashboard.el --- a dashboard for org roam  -*- lexical-binding: t; -*-

;; Copyright (C) 2020  

;; Author:  <joerg@joergvolbers.de>
;; Keywords: 

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Provides a dashboard for org roam.
;;
;; Calling `org-roam-dashboard' switches to the dashboard buffer. Use
;; 'g' to refresh the display.

;;; Code:

(require 'org-roam)
(require 'button)

;; * Variables

(defvar org-roam-dashboard-name "*Org Roam Dashboard*"
  "Name for the org roam dashboard buffer.")

;; * Link button

(define-button-type 'org-roam-dashboard-file-link
  'action 'org-roam-dashboard-follow-link-action)

(defun org-roam-dashboard-follow-link-action (button)
  (let* ((file-name (button-get button 'file)))
    (if (file-exists-p file-name)
	(find-file file-name)
      (error "File '%s' not available" file-name))))

(defun org-roam-dashboard-insert-link-button (file-name display-name)
  "Insert a button linking to FILE-NAME. "
  (insert-button display-name
		 'type 'org-roam-dashboard-file-link
		 'file file-name))

;; * Statistics button

(define-button-type 'org-roam-dashboard-statistics)

(defun org-roam-dashboard-pretty-number (n)
  (let* ((number-string (format "%d" n)))
    (reverse 
     (string-join (seq-partition (reverse number-string) 3)
		  "."))))
  
(defun org-roam-dashboard-insert-statistics-button (n &optional action-fn data title)
  "Insert a statistic button displaying the number N."
  (insert-button (org-roam-dashboard-pretty-number n)		 
		 'action (or action-fn #'ignore)
		 'data   data
		 'title  title))

;; * Query the last 10 modified files

(defun org-roam-dashboard-convert-mtime (file-list n)
  "Return FILE-LIST with item N interpreted as a special plist.
The item with the index number will be interpreted as a plist
with the key :mtime. Return FILE-LIST unmodified except that
item, which will be replaced by the value of :mtime."
  (seq-map (lambda (e)
	     (setf (seq-elt e n) (plist-get (nth n e) :mtime))
	     e)
	   file-list))

(defun org-roam-dashboard-last-modified-files (n)
  "Return the N last modified files."
  (let* (;; get all files                            n=0       1           2                3
	 (all-files (org-roam-db-query [:select [files:meta files:file titles:titles titles:file]
						:from files
						:left-join titles
						:on (= titles:file files:file)]))
	 ;; convert format to ("file" (mtime))
	 (mod-list  (org-roam-dashboard-convert-mtime all-files 0))
	 ;; sort by newest modification first
	 (sorted-files (seq-sort (lambda (e1 e2)
				   (time-less-p (car e2) (car e1)))
				 mod-list)))
    (seq-take sorted-files n)))

(defun org-roam-dashboard-truncate-string (s n)
  "Return string S truncated to N characers."
  (substring s 0 (when (> (length s) n) n)))

(defun org-roam-dashboard-insert-files (buf file-list &optional pos)
  "Insert FILE-LIST as a buttonized list in BUF at POS.
FILE-LIST must have the format (time-stamp file-name list-of-title-strings)."
  (with-current-buffer buf
    (let* ((inhibit-read-only t))
      (and pos (goto-char pos))
      (seq-doseq (item file-list)
	(let* ((time-string  (format-time-string "%D %T" (car item)))
	       (file-name    (nth 1 item))
	       (display-name (car (nth 2 item))))
	  (insert "  " time-string " ")
	  (org-roam-dashboard-insert-link-button file-name
						 (if display-name
						     (org-roam-dashboard-truncate-string display-name 80)
						   (file-name-nondirectory file-name)))
	  (insert "\n"))))))

;; * Get a list of the 'most linked' pages

(defun org-roam-dashboard-most-linked-pages ()
  "Get a list of the 'most linked' pages.
Returns a list of the format 

\(meta file-name titles file-name file-name count)."
  (org-roam-db-query
   [:select [ files:meta files:file titles:titles
	      titles:file links:to (as (funcall count links:to) a) ]
	    :from files
	    :left-join links
	    :on (= links:to files:file)
	    :left-join titles
	    :on (= titles:file files:file)
	    :group-by links:to
	    :order-by [(desc a)]
	    :limit 10]))

;; * Collect some interesting statistics

(defun org-roam-dashboard-orphaned-pages ()
  "Return a list of all orphaned pages.
The fields returned are (META FILENAME TITLES FILENAME)."
  (org-roam-db-query [:select [files:meta files:file titles:titles titles:file]
			      :from files
			      :left-join titles
			      :on (= files:file titles:file)
			      ;;(using file)
			      :where files:file
			      :not-in [:select to :from links]
			      :and files:file
			      :not-in [:select from :from links]]))

(defun org-roam-dashboard-all-files ()
  "Return a list of all files registered in org roam."
  (org-roam-db-query [:select [files:meta files:file] :from files]))

(defun org-roam-dashboard-flatten (l)
  "Flatten L.
This is a mere copy of dash's `-flatten'."
  (if (and (listp l) (listp (cdr l)))
      (seq-mapcat #'org-roam-dashboard-flatten l)
    (list l)))

(defun org-roam-dashboard-all-tags ()
  "Return a list of all tags registered in org roam."
  (seq-uniq 
   (org-roam-dashboard-flatten
    (org-roam-db-query [:select :distinct [tags:tags] :from tags]))))

(defun org-roam-dashboard-all-file-links ()
  "Return a list of all links between pages."
  (org-roam-db-query [:select [links:from links:type] :from links
			      :where (= type "file")]))

(defun org-roam-dashboard-go-to-file-list (button)
  "Show the file stored in BUTTON in a new buffer."
  (let* ((new-name   (concat (substring org-roam-dashboard-name 0 -1) "- Orphaned Files*"))
	 (buf        (or (get-buffer new-name) (generate-new-buffer new-name)))
	 (title      (button-get button 'title))
	 (file-list  (button-get button 'data)))
    (unless file-list
      (error "No files associated with this button"))
    (with-current-buffer buf
      (org-roam-dashboard-mode)
      (let* ((inhibit-read-only t))
	(erase-buffer)
	(when title
	  (insert title "\n"))
	(insert "\n")))
    (org-roam-dashboard-insert-files buf file-list)
    (org-roam-dashboard-make-intangible buf)
    (switch-to-buffer buf)))


;; * Dashboard major mode

(defvar org-roam-dashboard-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "g")  'org-roam-dashboard-update)
    map)
  "Key map for `lister-mode'.")

(define-derived-mode org-roam-dashboard-mode
  special-mode "roamdash"
  "Major mode for the org roam dashboard."
  (read-only-mode)
  (cursor-intangible-mode))

(defun org-roam-dashboard-all-buttons (buf)
  "Return a list of all buttons in BUF."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (let (res button)
	(while (and (not (eobp))
		    (setq button (next-button (point))))	  
	  (push button res)
	  (goto-char (button-end button)))
	res))))

(defun org-roam-dashboard-make-intangible (buf)
  "Make everything in BUF intangible except the first chars of the buttons."
  (with-current-buffer buf
    (goto-char (point-min))
    (let* ((inhibit-read-only t)
	   (buttons (org-roam-dashboard-all-buttons buf)))
      (put-text-property (point-min) (point-max)
			 'cursor-intangible t)
      (seq-doseq (button buttons)
	(goto-char (button-start button))
	(put-text-property (1- (point)) (point)
			   'cursor-intangible nil)))))

;; * Setting up the dashboard:

(defun org-roam-dashboard-update (buf)
  "Insert updated informations in BUF."
  (interactive (list (current-buffer)))
  (with-temp-message "Updating dashboard display..."
    (with-current-buffer buf
      (unless (derived-mode-p 'org-roam-dashboard-mode)
	(error "Buffer has to be on org-roam-dashboard mode"))
      (let* ((inhibit-read-only t))
	(erase-buffer)
	(insert "Org Roam Dashboard\n\n")
	;; Section: Overall statistics
	(let* ((all-files (org-roam-dashboard-all-files))
	       (all-links (org-roam-dashboard-all-file-links))
	       (all-tags  (org-roam-dashboard-all-tags)))
	  (insert (format "There are %s files registered, sharing %s tags and containing %s links.\n"
			  (org-roam-dashboard-pretty-number (length all-files))
			  (org-roam-dashboard-pretty-number (length all-tags))
			  (org-roam-dashboard-pretty-number (length all-links))))
	  (insert "\n"))
	;; Section: Last modified files 
	(insert "Last modified files:\n\n")
	(org-roam-dashboard-insert-files buf (org-roam-dashboard-last-modified-files 10))
	(insert "\n")
	;; Section: Orphaned Pages
	(let* ((orphaned-files (org-roam-dashboard-orphaned-pages)))
	  (insert "  There are ")
	  (org-roam-dashboard-insert-statistics-button (length orphaned-files)
						       #'org-roam-dashboard-go-to-file-list
						       (org-roam-dashboard-convert-mtime orphaned-files 0)
						       "Orphaned files:")
	  (insert " 'orphaned' files without any links.\n\n"))
	;; Section: Most linked pages
	(let* ((most-linked (org-roam-dashboard-most-linked-pages))
	       (better-list (org-roam-dashboard-convert-mtime most-linked 0)))
	  (insert " The ten most linked to files:\n\n")
	  (org-roam-dashboard-insert-files buf better-list)
	  (insert "\n"))
	;; Section: Blabla
	(insert "Press `g' to update the display, `q' to bury the buffer, or `enter' on a button.")
	;; --- 
	(org-roam-dashboard-make-intangible (current-buffer))
	(goto-char (point-min))
	(forward-button 1)))
    buf))

;;;###autoload
(defun org-roam-dashboard ()
  "Visit org roam dashboard."
  (interactive)
  (unless org-roam-mode (org-roam-mode))
  (let* ((buf (or (get-buffer org-roam-dashboard-name))))
    (unless buf
      (setq buf (generate-new-buffer org-roam-dashboard-name))
      (with-current-buffer buf
	(org-roam-dashboard-mode))
      (org-roam-dashboard-update buf))
    (switch-to-buffer buf)))

(provide 'org-roam-dashboard)
;;; org-roam-dashboard.el ends here
