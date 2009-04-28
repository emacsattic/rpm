;;; rpm.el --- Front end for rpm (the RedHat Package Manager) now widely
;;             in use on GNU/Linux systems.

;;   Copyright (C) 1998  Detlev Zundel
;;   Version 1.2

;; This file is NOT part of GNU Emacs.

;;
;;   This program is free software; you can redistribute it and/or
;;   modify it under the terms of the GNU General Public License
;;   as published by the Free Software Foundation; either version 2
;;   of the License, or (at your option) any later version.
;;
;;   This program is distributed in the hope that it will be useful,
;;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;   GNU General Public License for more details.
;;
;;   You should have received a copy of the GNU General Public License
;;   along with this program; if not, write to the Free Software
;;   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

;; LCD Archive Entry:
;; rpm|Detlev Zundel|Detlev.Zundel@stud.uni-karlsruhe.de|
;; Front end for rpm (the RedHat Package Manager) utility|
;; $Date: 1998/10/27 02:22:41 $|Version 1.2||

;;; Commentary:
;;

;; This mode provides sort of a  dired buffer to interact with the rpm
;; utility used on some GNU/Linux systems to manage software packages.
;; The mode starts  up by displaying all installed  packages.  You can
;; then  get  detailed informations  on  a  specific package,  verify,
;; install/uninstall  a package  or check/list  dependencies.   In the
;; detailed information buffer you  can easily visit listed files e.g.
;; to  check readme's or  other documentation  stuff.  rpm  also hooks
;; into  dired mode, so  you can  directly install  a file  (or tagged
;; files) from a dired buffer.
;;
;; It's  generally a nice way to  browse  through the packages without
;; having to remember the syntax of rpm ;)

;; Installation:

;; In order to  use this package, you need   Elib, the GNU Emacs  lisp
;; library (I  use version 1.0). You  can get the latest  version from
;; `ftp.lysator.liu.se' in  `pub/emacs'  with anonymous ftp.   Be sure
;; that  the files  of the Elib  package  are in your  `load-path'. If
;; you're not sure whether you've got  the package already try `locate
;; cookie.elc' (or something like `find / -name cookie.elc -print').
;;
;; To use  the rpm-mode  put the source-file  (or better  the compiled
;; version)  somewhere  where  it  can  be found  (i.e.  somewhere  in
;; `load-path') and  include the  following expression in  your .emacs
;; file (or wherever...)
;;
;; (autoload 'rpm "rpm"
;;      "Shell for the rpm package management utility." t)
;; (autoload 'rpm-dired-install "rpm"
;;      "Install all marked (or next ARG) rpm-files." t)
;; (add-hook 'dired-load-hook
;;        '(lambda () (define-key dired-mode-map "I"
;;                      'rpm-dired-install)))
;;
;; You can  then start it  up by `M-x rpm'.   `describe-mode' (usually
;; bound to  C-h m) gives you  help on the  other available functions.
;; The second and  the third form define `I'  in dired-mode to install
;; the tagged files or the file on the current line.
;;
;; If you  have a  display capable of  color you might  enjoy enabling
;; font-lock-mode to get  colored marks. This will also  work if hl319
;; was loaded before rpm.
;;
;; As this  package is mostly  a (hopefully comfortable)  interface to
;; "rpm"  you should  consult the  rpm documentation  about  the exact
;; functionality  of  the individual  commands  (especially about  the
;; exact functionality  of the  command-line switches).  This  said, I
;; can assure  you that most  of the commands  work just as  one would
;; expect them to..

;; Send bug/problem reports or anything connected to rpm.el to:
;; Detlev.Zundel@stud.uni-karslruhe.de

;; $Id: rpm.el,v 1.4 1998/10/27 02:22:41 dzu Exp $
;; (The revision number does not have to coincide with the version
;; number)

;;; History:
;;

;; Changes from Version 1.1:
;;   - The verify, install and uninstall actions are now
;;     asynchronous processes
;;   - Deletion of packages is now similar to dired-mode by first
;;     flagging them for deletion and then executing the deletions in
;;     one batch
;;   - Batch processing for verify/require now available through
;;     marking of packages
;;   - Added menu support
;;   - Entering options supports completion
;;   - Added customization
;;   - Easy switch between two index formats
;;   - Format(s) of index entries can be customized
;;   - Added font-lock / hl319 support (only for marks right now)
;;   - Packages can now also be sorted by "install-date"
;;   - Easy interface to the "rpm" man page
;;   - (More or less) consistent mouse support
;;   - Improved buffer handling
;;   - Lots of cleanup in the code ;)

;;; Code:

;; Cookie belongs to the E-Lib package and makes life so much more
;; comfortable....
(require 'cookie)

;; In pre-20 versions (when ..) is not in the standard library.
(eval-and-compile
  (if (not (fboundp 'when))
      (defmacro when (cond &rest body)
        "(when COND BODY...): if COND yields non-nil, do BODY, else return nil."
        (list 'if cond (cons 'progn body))))
  (if (not (fboundp 'unless))
      (defmacro unless (cond &rest body)
        "(unless COND BODY...): if COND yields nil, do BODY, else return nil."
        (cons 'if (cons cond (cons nil body))))))

;; When we compile we need the dired macros. We don't require it
;; otherwise as the only function that needs it (rpm-dired-install)
;; can only be called from dired.
(eval-when-compile
  (require 'dired))

;;
;; This section describes the globals used by rpm
;;

;; Customizable variables

;; This is stolen from w3-cus.el to ignore the defgroup and use defvar
;; instead of defcustom if they are not available.
(eval-and-compile
  (condition-case ()
      (require 'custom)
    (error nil))
  (if (and (featurep 'custom) (fboundp 'custom-declare-variable))
      nil ;; We've got what we needed
    ;; We have the old custom-library, hack around it!
    (defmacro defgroup (&rest args)
      nil)
    (defmacro defcustom (var value doc &rest args)
      (` (defvar (, var) (, value) (, doc))))))

(defgroup rpm nil
  "Options for the rpm major mode."
  :group 'unix
  :prefix "rpm-")

(defcustom rpm-index-format
  "%-14n (%7.1KkB) - Version: %v / Release %r"
  "*String specifying the display of packages in the index list.
Constructs of the form \"%c\" are replaced by attributes of the package
where c can be one of the following:

n - The name of the package.
v - The version.
r - The release.
B - The size in bytes.
K - The size in kilobytes.
M - The size in megabytes.
t - The installation time.  (fixed length of 8 chars)
d - The installation date.  (fixed length of 10 chars and sensitive
                             to `european-calendar-style')

Where appropriate you can insert a width specification before the
command characters (see format).  For example \"%7.1K\" prints the size
7 characters wide with one decimal or \"%-14n\" pads the name with
spaces to the right to use up 14 characters.

You can specify an alternate format, e.g. with more information, with
the rpm-alt-index-format variable."
  :group 'rpm
  :type 'string)

(defcustom rpm-alt-index-format
  "%-14n (%7.1KkB) - [%t %d] - Version: %v"
  "*Alternate format specification for the index.
For documentation see `rpm-index-format'."
  :group 'rpm
  :type 'string)

(defcustom rpm-sort-crit
  'name
  "*Specifies the sorting order for the index.
Can be 'name, 'size or 'install-date."
  :group 'rpm
  :type '(choice (const name)
                 (const size)
                 (const install-date)))

(defcustom rpm-reverse-sort nil
  "*Invert canonical sort order if non-nil."
  :group 'rpm
  :type 'boolean)

(defcustom rpm-binary "/bin/rpm"
  "*The name of the binary to use."
  :group 'rpm
  :type 'string)

;; End of customizable variables

(defvar rpm-lemacs
  (string-match "\\(Lucid\\|Xemacs\\)" emacs-version)
  "Non-nil when running under under Lucid Emacs or Xemacs.")

(defvar rpm-shared-keymap nil)
(if (not rpm-shared-keymap)
    (progn
      (setq rpm-shared-keymap (make-sparse-keymap))
      ;; Suppress the self inserting characters
      (suppress-keymap rpm-shared-keymap)
      (define-key rpm-shared-keymap "v" 'rpm-view)
      (define-key rpm-shared-keymap [ 13 ] 'rpm-visit)
      (define-key rpm-shared-keymap "q" 'rpm-quit)
      (define-key rpm-shared-keymap "y" 'rpm-verify)
      (define-key rpm-shared-keymap "r" 'rpm-requires)
      (define-key rpm-shared-keymap "i" 'rpm-install)
      (define-key rpm-shared-keymap "f" 'rpm-locate-package)
      (define-key rpm-shared-keymap "M" 'rpm-man)
      (define-key rpm-shared-keymap "\C-c\C-c" 'rpm-interrupt)
      (define-key rpm-shared-keymap [S-mouse-2] 'rpm-quit)
      (define-key rpm-shared-keymap [mouse-2] 'rpm-visit-mouse)))

(defvar rpm-shared-menu-map nil)
(if (not rpm-shared-menu-map)
    (if rpm-lemacs
        ()
      (setq rpm-shared-menu-map (make-sparse-keymap "Rpm"))
      (define-key rpm-shared-menu-map [quit]
        '("Quit buffer"  . rpm-quit))

      (define-key rpm-shared-menu-map [man]
        '("Manual for rpm"  . rpm-man))
      (define-key rpm-shared-menu-map [install]
        '("Install a package"  . rpm-install))
      (define-key rpm-shared-menu-map [find-file]
        '("Find package for a file"  . rpm-locate-package))
      (define-key rpm-shared-menu-map [requires]
        '("Requirements for package(s)" . rpm-requires))
      (define-key rpm-shared-menu-map [verify]
        '("Verify package(s)" . rpm-verify))
      (define-key rpm-shared-menu-map [visit]
        '("Visit"  . rpm-visit))
      ))

(defvar rpm-output-mode-map nil)
(if (not rpm-output-mode-map)
    (progn
      (setq rpm-output-mode-map (make-sparse-keymap))
      (set-keymap-parent rpm-output-mode-map rpm-shared-keymap)
      (if rpm-shared-menu-map
          (define-key rpm-output-mode-map [menu-bar rpm]
            (cons "Rpm" rpm-shared-menu-map)))))

(defvar rpm-index-mode-map nil)
(if (not rpm-index-mode-map)
    (progn
      (setq rpm-index-mode-map (make-sparse-keymap))
      (set-keymap-parent rpm-index-mode-map rpm-shared-keymap)
      (define-key rpm-index-mode-map "s" 'rpm-set-sort)
      (define-key rpm-index-mode-map "S" 'rpm-invert-sort)
      (define-key rpm-index-mode-map "d" 'rpm-mark-delete)
      (define-key rpm-index-mode-map "m" 'rpm-mark)
      (define-key rpm-index-mode-map "u" 'rpm-unmark)
      (define-key rpm-index-mode-map "U" 'rpm-unmark-all)
      (define-key rpm-index-mode-map "x" 'rpm-execute)
      (define-key rpm-index-mode-map "g" 'rpm-rebuild-index)
      (define-key rpm-index-mode-map "D" 'rpm-toggle-format)

      (if rpm-shared-menu-map
          (let ((keymap (make-sparse-keymap "Rpm")))
            (set-keymap-parent keymap rpm-shared-menu-map)
            (define-key keymap [sort-order]
              (cons "Sort order" (make-sparse-keymap "Sort order")))
            (define-key keymap [sort-order invert-sort]
              '("Invert sort order"  . rpm-invert-sort))
            (define-key keymap [sort-order install-date]
              '("By installation date"  . rpm-set-sort-by-install-date))
            (define-key keymap [sort-order size]
              '("By size"  . rpm-set-sort-by-size))
            (define-key keymap [sort-order name]
              '("By name"  . rpm-set-sort-by-name))

            (define-key keymap [unmark-all]
              '("Unmark all packages"  . rpm-unmark-all))
            (define-key keymap [uninstall]
              '("Un-install flagged package(s)"  . rpm-execute))

            (define-key rpm-index-mode-map [menu-bar rpm]
              (cons "Rpm" keymap))))))

(defvar rpm-crumb-box nil
  "Container for the cookie collection.")
(defvar rpm-proc nil
  "If rpm runs in the background this variable holds the process.")
(defvar rpm-proc-msg ""
  "String identifying the current action of the background rpm process.")
(defvar rpm-after-finish-proc nil
  "Function that will be called after the background process has finished.")
(defvar rpm-package-name nil
  "Contains the name of the package associated with the buffer.")
(defvar rpm-tag-string ""
  "Contains a summary of the tagged packages for the mode-line.")
(defvar rpm-tag-d-size 0
  "Sum of the package sizes that were flagged for deletion.")
(defvar rpm-format-used 'rpm-index-format
  "Specifies which format is used to display the index.
Can be `rpm-index-format' or `rpm-alt-index-format'.")
(defvar rpm-index-mode-hook nil
  "Run after putting the buffer in `rpm-index-mode'.")
(defvar rpm-output-mode-hook nil
  "Run after putting the buffer in `rpm-output-mode'.")

;; font-lock-warning-face seems to be new in 20.xx
(if (not (facep 'font-lock-warning-face))
    (progn
      (make-face 'font-lock-warning-face)
      (copy-face 'bold 'font-lock-warning-face)
      (set-face-foreground 'font-lock-warning-face "red")
      (setq font-lock-warning-face 'font-lock-warning-face)))
(defvar rpm-font-lock-keywords
  (list
   ;; Marked packages
   '("^\* .+$" . font-lock-keyword-face)
   ;; Packages flagged for deletion
   '("^D .+$" . font-lock-warning-face))
  "How to display marked packages in rpm.")
;; Support for the hl319 package (load hl319 before rpm!)
(if (memq 'hl319 features)
    (hilit-set-mode-patterns
     'rpm-index-mode
     '((:buildme:
        (marked "^\* .+$")
        (error  "^D .+$")
        ))))

;;; The buffers we use
(defconst rpm-buf-temp "*rpm temporary*"
  "The name of the buffer to hold temporary output of rpm.")
(defconst rpm-buf-index "*rpm-index*"
  "The name of the buffer to hold the index of all packages.")
(defconst rpm-buf-rpm-out "*rpm-out*"
  "The name of the buffer to hold the output of rpm.")

(defconst rpm-header-text "Installed packages :\n"
  "Specifies the text inserted at the top of the index buffer.")

;;; The switches for the individual actions
(defconst rpm-opts-listall '("-qia")
  "Option(s) for listing all packages including info.")
(defconst rpm-opts-flist '("-qil")
  "Option(s) for listing info and all files for a package.")
(defconst rpm-opts-find-flist '("-qf")
  "Option(s) to list name of the package that a given file belongs to.")
(defconst rpm-opts-verify '("-V")
   "Option(s) to verify all files of a package.")
(defconst rpm-opts-requires '("-q" "--requires")
  "Option(s) to find out what other packages are required.")
(defconst rpm-opts-install '("-i")
  "Option(s) to install a new package.")
(defconst rpm-opts-uninstall '("-e")
  "Option(s) to install a new package.")

;;; Possible switches for the completion
(defconst rpm-all-opts-general
  (mapcar '(lambda (el) (cons (concat el " ") 1))
          '("-vv" "--quiet" "--version" "--keep-temps" "--rcfile" "--root"))
  "Possible options for all different modes.")
(defconst rpm-all-opts-install
  (append
   rpm-all-opts-general
   (mapcar '(lambda (el) (cons (concat el " ") 1))
           '("--force" "--hash" "--oldpackage" "--percent"
             "--replacefiles" "--replacepkgs" "--nodeps"
             "--excludedocs" "--includedocs" "--test" "--upgrade")))
  "Possible options for install.")
(defconst rpm-all-opts-uninstall
  (append
   rpm-all-opts-general
   (mapcar '(lambda (el) (cons (concat el " ") 1))
           '("--allmatches" "--noscripts" "--nodeps" "--test")))
  "Possible options for un-install.")

(defvar rpm-complete-keymap nil
  "The keymap for option completion.")
(if (not rpm-complete-keymap)
    (progn
      (setq rpm-complete-keymap (copy-keymap minibuffer-local-map))
      (define-key rpm-complete-keymap [ tab ] 'rpm-complete-option)))

;;
;; rpm starts up an index buffer
;;

;;;###autoload
(defun rpm ()
  "Shell for the rpm package management utility."
  (interactive)

  (let ((buf-existed (get-buffer rpm-buf-index)))
    (switch-to-buffer rpm-buf-index)
    (when (not buf-existed)
      (rpm-index-mode)
      (rpm-rebuild-crumb-box))))

;;
;; The index buffer and individual package buffers all use the rpm
;; major mode. The index buffer alone uses a superset of the keymap
;; available in the other buffers and supports font-lock-mode.
;;
(defun rpm-index-mode ()
  "Major mode for interacting with the package utility rpm.

Available commands:
\\<rpm-index-mode-map>
\\[rpm-quit]  Quit the current buffer and kill all temporary buffers
\\[rpm-visit]  Visit the package at point
\\[rpm-verify]  Verify the package(s)
\\[rpm-requires]  List all required packages for the package(s)
\\[rpm-locate-package]  Find the package that a specified file belongs to
\\[rpm-install]  Install a package (you should have the rights to do so..)
\\[rpm-mark-delete]  Flag current (or next ARG) packages for deletion
\\[rpm-execute]  Uninstall the packages flagged for deletion (see install..)
\\[rpm-mark]  Mark current (or next ARG) packages for subsequent processing
\\[rpm-unmark]  Unmark current (or next ARG) previously marked packages
\\[rpm-unmark-all]  Unmark all packages
\\[rpm-set-sort]  Set the sorting criterion
\\[rpm-invert-sort]  Invert the current sort order
\\[rpm-rebuild-index]  Rebuild the index
\\[rpm-toggle-format]  Switch between default and alternate display format
\\[rpm-man]  Show the man-page for rpm
\\[rpm-interrupt]  Cancel current background operation."

  (kill-all-local-variables)
  (make-local-variable 'rpm-package-name)
  (setq buffer-undo-list  t             ;Disable undo
        indent-tabs-mode  nil           ;Do not use tab characters
        major-mode       'rpm-index-mode
        mode-name        "Rpm Index"
        rpm-package-name nil
        rpm-tag-string   ""
        rpm-tag-d-size   0
        mode-line-buffer-identification
        '(25 . ("%b" rpm-tag-string)))
  (use-local-map rpm-index-mode-map)
  ;; Setup font-lock support
  (make-local-variable 'font-lock-defaults)
  (setq font-lock-defaults '(rpm-font-lock-keywords t))
  ;; If hl319 is loaded use it (but don't loose control in case
  ;; of an error)
  (if (memq 'hl319 features)
      (condition-case nil
          (hilit-install-line-hooks)))
  (run-hooks 'rpm-index-mode-hook))

(defun rpm-output-mode ()
  "Major mode for interacting with the package utility rpm.

Available commands (see also the help in the index):
\\{rpm-output-mode-map}"

  (kill-all-local-variables)
  (make-local-variable 'rpm-package-name)
  (setq buffer-undo-list  t             ;Disable undo
        indent-tabs-mode  nil           ;Do not use tab characters
        major-mode       'rpm-output-mode
        mode-name        "Rpm Output"
        rpm-package-name nil
        mode-line-buffer-identification
        '(25 . (rpm-package-name ("RPM-Pkg. " rpm-package-name))))
  (use-local-map rpm-output-mode-map)
  (run-hooks 'rpm-output-mode-hook))

;; The administration and display of the index is delegated to the
;; cookie package. We only provide a pretty printer, a sort predicate
;; and a function to build the collection.

;; The crumb-box contains all the "package-cookies" which in turn are
;; alists describing the packages
(defun rpm-rebuild-crumb-box ()
  "Rebuild the cookie collection."
  (if (get-buffer rpm-buf-index)
      (progn
        (save-excursion
          (set-buffer (get-buffer rpm-buf-index))
          (setq buffer-read-only nil)
          (delete-region (point-min) (point-max))
          (setq buffer-read-only t)
          (setq rpm-tag-d-size 0
                rpm-tag-string "")
          (setq rpm-crumb-box (collection-create
                               (current-buffer)
                               'rpm-cookie-print
                               rpm-header-text))
          (collection-set-goal-column rpm-crumb-box 2)
          (collection-append-cookies rpm-crumb-box (rpm-build-cookie-list)))
        (rpm-sort-index))))

;; Parse the output of rpm and build an alist for each package
(defun rpm-build-cookie-list ()
  "Build list of package descriptions (alists) from rpm output."
  (message "Building index...")
  (let ((tmpbuf (get-buffer-create rpm-buf-temp))
        (month-alist '(("Jan" . 1) ("Feb" . 2)
                       ("Mar" . 3) ("Apr" . 4)
                       ("May" . 5) ("Jun" . 6)
                       ("Jul" . 7) ("Aug" . 8)
                       ("Sep" . 9) ("Oct" . 10)
                       ("Nov" . 11) ("Dec" . 12)))
        list alist)
    (save-excursion
      (set-buffer tmpbuf)
      (rpm-call-rpm-sync (append (list rpm-binary) rpm-opts-listall) nil)
      (goto-char (point-min))
      (while (re-search-forward "Name\\W*:\\W+\\(\\w[^ \t]*\\)" (point-max) t)
        (setq alist (list (cons 'name (match-string 1))))
        (re-search-forward "Version\\W*:\\W+\\(\\w[^ \t]*\\)" (point-max) t)
        (setq alist (append alist (list (cons 'version (match-string 1)))))
        (re-search-forward "Release\\W*:\\W+\\(\\w[^ \t]*\\)" (point-max) t)
        (setq alist (append alist (list (cons 'release (match-string 1)))))
        (re-search-forward
         "Install date\\W*:\\W+\\w\\w\\w \\(\\w\\w\\w\\) \\([0-9][0-9]\\) \\([0-9:]+\\) \\([0-9]+\\)"
         (point-max) t)
        (setq alist
              (append alist
                      (list (list 'install-date
                                  (cdr (assoc (match-string 1) month-alist))
                                  (string-to-number (match-string 2))
                                  (string-to-number (match-string 4)))
                            (cons 'install-time (match-string 3)))))
        (re-search-forward "Size\\W*:\\W+\\([0-9]+\\)" (point-max) t)
        (setq alist (append alist (list
                                   (cons 'size
                                         (string-to-int (match-string 1))))))
        (setq alist (append alist (list
                                   (cons 'tag nil))))
        (setq list (append list (list alist)))
        )
      (kill-buffer tmpbuf))
    (message "Building index...done")
    list              ; return the list
    ))

(defun rpm-cookie-print (cookie)
  "Print a configurable represantation of a COOKIE."
  (let ((fmt (eval rpm-format-used)))
    (while (string-match "\\(%[-]*[0-9]*[.]*[0-9]*\\)\\(.\\)" fmt)
      (let ((cchar (string-to-char (match-string 2 fmt)))
            (fspec (match-string 1 fmt)))
        (setq fmt
              (concat (substring fmt 0 (match-beginning 0))
                      (cond
                       ;; The name is clickable
                       ((eq cchar ?n)
                        (let (name)
                          (setq name
                                (format (concat fspec "s")
                                        (cdr (assoc 'name cookie))))
                          (unless rpm-lemacs
                            (set-text-properties 0 (length name)
                                                 '(mouse-face highlight)
                                                 name))
                          name))
                       ;; Size in bytes (integer value)
                       ((eq cchar ?B)
                        (format (concat fspec "d")
                                (cdr (assoc 'size cookie))))
                       ;; Size in kilobytes (float value)
                       ((eq cchar ?K)
                        (format (concat fspec "f")
                                (/ (float (cdr (assoc 'size cookie)))
                                    1024)))
                       ;; Size in megabytes (float value)
                       ((eq cchar ?M)
                        (format (concat fspec "f")
                                (/ (float (cdr (assoc 'size cookie)))
                                    (* 1024 1024))))
                       ;; Version
                       ((eq cchar ?v)
                        (format (concat fspec "s")
                                (cdr (assoc 'version cookie))))

                       ;; Release
                       ((eq cchar ?r)
                        (format (concat fspec "s")
                                (cdr (assoc 'release cookie))))
                       ;; Installation date
                       ((eq cchar ?d)
                        (let* ((date (cdr (assoc 'install-date cookie)))
                               (mon (car date))
                               (day (car (cdr date)))
                               (year (car (cdr (cdr date)))))
                          (if european-calendar-style
                              (format "%02d.%02d.%04d" day mon year)
                          (format "%02d/%02d/%04d" mon day year))))
                       ;; Installation time
                       ((eq cchar ?t)
                        (format "%s"
                                (cdr (assoc 'install-time cookie))))
                       (t
                        (error "Wrong format specifier")))
                      (substring fmt (match-end 0))))))
    ;; Tag marked packages with a character (and a different face
    ;; via font-lock-mode)
    (let ((tag (cdr (assoc 'tag cookie))))
      (setq fmt (concat
                 (cond ((eq tag 'to-be-deleted) "D")
                       ((eq tag 'marked)        "*")
                       (t                       " "))
                 " " fmt)))
    (insert fmt)))

(defun rpm-sort-index ()
  "Sort the cookie collection."
  (message "Sorting the index...")

  (cookie-sort rpm-crumb-box 'rpm-cookie-compare)
  (tin-goto rpm-crumb-box (tin-nth rpm-crumb-box 0))
  (message "Sorting the index...done"))

(defun rpm-cookie-compare (cookie1 cookie2)
  "Compare COOKIE1 and COOKIE2 as determined by current sorting order."
  (let (result)
    (setq result
          (cond
           ((eq rpm-sort-crit 'size)
            ;; Canonical sort order is descending (biggest first)
            (> (cdr (assoc 'size cookie1))
               (cdr (assoc 'size cookie2))))
           ((eq rpm-sort-crit 'name)
            ;; Canonical sort order is ascending (a ... z)
            (string-lessp (cdr (assoc 'name cookie1))
                          (cdr (assoc 'name cookie2))))
           ((eq rpm-sort-crit 'install-date)
            ;; Canonical sort order is descending (newest first)
            (let ((date1 (cdr (assoc 'install-date cookie1)))
                  (date2 (cdr (assoc 'install-date cookie2))))
              ;; Second sort criterion is the name - but independent of the
              ;; primary sorting order always ascending
              (if (equal date1 date2)
                  (rpm-xor rpm-reverse-sort
                           (string-lessp (cdr (assoc 'name cookie1))
                                         (cdr (assoc 'name cookie2))))
                (not (rpm-date-lessp date1  date2)))))
           (t
            (error "Invalid sort criterion specified in rpm-sort-crit"))))
    (rpm-xor rpm-reverse-sort result)
  ))

;;
;; Below are low-level helper functions
;;

;; Time intensive tasks are run in the background
(defun rpm-call-rpm-async (argv msg &optional func)
  "Call rpm asynchronously with arguments ARGV displaying MSG.
Optional FUNC is called rpm exits."
  (when rpm-proc
      (error "Process rpm is already active in the background"))
  (setq rpm-proc
        (apply 'start-process "rpm" (current-buffer) (car argv)
               (cdr argv)))
  (set-process-sentinel rpm-proc 'rpm-proc-sentinel)
  (setq rpm-proc-msg msg
        rpm-after-finish-proc func
        mode-line-process ":run")
    (message (concat msg "...")))

(defun rpm-proc-sentinel (process event)
  "Clean up after PROCESS exited with EVENT."
  (setq rpm-proc nil)
  (let ((buffer (process-buffer process)))
    ;; Is the buffer still alive?
    (when (buffer-name buffer)
      (save-excursion
        (set-buffer buffer)
        (setq buffer-read-only nil)
        (display-buffer buffer)
        (message (concat rpm-proc-msg "...Done"))
        ;; If the caller of rpm-run-async wants to react to the
        ;; results of the background process, he gets the chance to do
        ;; so now.
        (when rpm-after-finish-proc
          (funcall rpm-after-finish-proc (process-exit-status process)))
        (insert "\n" event)
        (setq buffer-read-only t
              mode-line-process nil)))))

;; As the synchronous process can overlap the asynchronous one it
;; should only be called for short read operations.
(defun rpm-call-rpm-sync (args redisplay)
  "Call rpm with ARGS.  If REDISPLAY is t then redisplay buffer."
  (apply 'call-process (car args) nil t redisplay (cdr args)))

(defun rpm-date-lessp (date1 date2)
  "Return t if DATE1 precedes DATE2."
  (< (+ (* (nth 2 date1) 365) (* (nth 0 date1) 31) (nth 1 date1))
     (+ (* (nth 2 date2) 365) (* (nth 0 date2) 31) (nth 1 date2))))

(defun rpm-extract-name (cookie)
  "Extract the full name from COOKIE."
  (concat (cdr (assoc 'name cookie))
          "-" (cdr (assoc 'version cookie))
          "-" (cdr (assoc 'release cookie))))

(defun rpm-is-marked (cookie &optional type)
  "Check whether COOKIE is marked.
If optional TYPE is given then the mark has to be of that type."
  (if type
      (eq (cdr (assoc 'tag cookie)) type)
    (cdr (assoc 'tag cookie))))

(defun rpm-marked (type)
  "Build list of all cookies marked with TYPE."
  (mapcar 'rpm-extract-name
          (collection-collect-cookie rpm-crumb-box
                                     'rpm-is-marked
                                     type)))

(defun rpm-package-at-pos (pos)
  "Return name of the package at POS."
  (let ((cookie (tin-cookie rpm-crumb-box (tin-locate rpm-crumb-box pos))))
    (rpm-extract-name cookie)))

(defun rpm-build-arglist ()
  "Return argument list for a command.
This is the package at point or the marked packages if such exist."
  (let* ((pkgs (rpm-marked 'marked))
         (count (length pkgs)))
    (if (> count 0)
        pkgs
      (list (rpm-package-at-pos (point))))))

;; If there is only one argument for a command it gets a buffer with
;; the name of the package. Otherwise the output goes to the
;; rpm-buf-rpm-out buffer.
(defun rpm-buffer-for-args (arglist)
  "Return name of buffer to use for output of command with ARGLIST."
  (if (eq 1 (length arglist))
      (car arglist)
    rpm-buf-rpm-out))

(defun rpm-set-clear-buf (bufname)
  "Set and clear buffer BUFNAME."
  (switch-to-buffer bufname)
  (setq buffer-read-only nil)
  (delete-region (point-min) (point-max))
  (rpm-output-mode)
  (display-buffer bufname))

;; This uses completion - a nasty detail is that mouse-2 in the
;; completion buffer replaces the entire mini-buffer. This should be
;; fixed sometime.
(defun rpm-read-options (prompt options)
  "Display PROMPT and read options for rpm with completion.
The possible completions OPTIONS is an alist with the options as keys."

  (let ((rpm-opt-list options))
    (read-from-minibuffer prompt "" rpm-complete-keymap)))

;; Note that rpm-opt-list is only dynamically bound
;; by rpm-read-options
(defun rpm-complete-option ()
  "Complete option before point.
The variable `rpm-opt-list' has to be bound to the possible options."
  (interactive)

  (let (beg pattern completion)
    (setq beg
          (save-excursion (skip-chars-backward "^\t ") (point)))
    (setq pattern
          (buffer-substring beg (point)))
    (setq completion (try-completion pattern rpm-opt-list))
    (cond ((eq completion t))
          ((null completion)
           (message "Can't find completion for \"%s\"" pattern)
           (ding))
          ((not (string= pattern completion))
           (delete-region beg (point))
           (insert completion))
          (t
           (with-output-to-temp-buffer "*Completions*"
             (display-completion-list
              (all-completions pattern rpm-opt-list nil)))))))

;; split-string is not in the 19.xx versions
(defun rpm-split-string (string)
  "Split STRING on white spaces."
  (let (list)
    (while (> (length string) 0)
      (if (string-match "^[ \f\t\n\r\v]+" string)
          (setq string (substring string (match-end 0))))
      (if (string-match "^[^ \f\t\n\r\v]+" string)
          (progn
            (setq list (append list (list (match-string 0 string))))
            (setq string (substring string (match-end 0))))))
    list))

(defun rpm-update-tag-string ()
  "Update the tag string displayed in the mode-line."
  (setq rpm-tag-string
        (concat (if (> rpm-tag-d-size 0)
                  (format " - Delete %6.1fkB"
                          (/ rpm-tag-d-size 1024))
                  ""))))

(defun rpm-visited-pkg ()
  "Return package associated with this buffer."
  (or rpm-package-name
      (error "No package is associated with this buffer")))

(defun rpm-filename-at-point ()
  "Return filename at point."
  (save-excursion
    (let* ((fnchars "~/A-Za-z0-9---_.${}#%,:")
           (beg (save-excursion (skip-chars-backward fnchars) (point)))
           (end (save-excursion (skip-chars-forward fnchars) (point))))
      (if rpm-lemacs
          (buffer-substring beg end)
      (buffer-substring-no-properties beg end)))))

(defun rpm-xor (a b)
  "Exclusive or of A and B."
  (or (and a (not b))
      (and (not a) b)))

;;
;; These functions do most of the work
;;

(defun rpm-do-install (files &optional options)
  "Install FILES using rpm with optional OPTIONS."

  (if (null options)
      (setq options (rpm-read-options
                     "Additional install options (see man-page): "
                     rpm-all-opts-install)))

  (let (argv status)
    (rpm-set-clear-buf rpm-buf-rpm-out)
    (insert (format "Installing %s:\n\n"
                    (if (eq (length files) 1)
                        (car files)
                      "the marked packages")))
    (setq argv (append (list rpm-binary)
                       rpm-opts-install
                       (rpm-split-string options)
                       (mapcar 'expand-file-name files)))
    (setq rpm-package-name nil)
    (rpm-call-rpm-async
     argv
     "Installing"
     (function (lambda (status)
                 (when (eq status 0)
                   (rpm-rebuild-crumb-box)))))
    ))

(defun rpm-do-requires (pkgs)
  "Determine which packages are required for PKGS."

  (rpm-set-clear-buf (rpm-buffer-for-args pkgs))
  (insert (format "The %s the package(s):\n\n"
                  (if (eq (length pkgs) 1)
                      (concat "package " (car pkgs) " requires")
                    "marked packages require")))
  (rpm-call-rpm-sync (append (list rpm-binary) rpm-opts-requires pkgs) t)
  (if (eq (length pkgs) 1)
      (setq rpm-package-name (car pkgs))
    (setq rpm-package-name nil))
  (setq buffer-read-only t))

(defun rpm-do-uninstall (pkgs &optional options)
  "Un-install package(s) PKGS using rpm with optional OPTIONS."

  (if (null options)
      (setq options (rpm-read-options
                     "Additional uninstall options (see man-page): "
                     rpm-all-opts-uninstall)))
  (let (argv status)
    (rpm-set-clear-buf (rpm-buffer-for-args pkgs))
    (insert (format "Un-installing %s:\n\n"
                    (if (eq (length pkgs) 1)
                        (car pkgs)
                      "the marked packages")))
    (setq argv (append (list rpm-binary)
                       rpm-opts-uninstall
                       (rpm-split-string options)
                       pkgs))
    (rpm-call-rpm-async
     argv
     "Uninstalling"
     (function (lambda (status)
                 (if (eq status 0)
                     (progn
                       (setq rpm-package-name nil)
                       (rpm-rebuild-crumb-box))))))
    ))

(defun rpm-do-verify (pkgs)
  "Verify the state of installed package(s) PKGS using rpm."

  (let (argv old-point)
    (rpm-set-clear-buf (rpm-buffer-for-args pkgs))
    (insert (format "Verifying %s:\n\n"
                    (if (eq (length pkgs) 1)
                        (car pkgs)
                      "the marked packages")))
    (setq old-point (point))
    (setq argv (append (list rpm-binary)
                       rpm-opts-verify
                       pkgs))
    (push-mark (1- (point)) t)
    (rpm-call-rpm-async
     argv
     "Verifying"
     (function (lambda (status)
                 (setq buffer-read-only nil)
                 (if (not (re-search-backward "[^\\s ]" (1+ (mark)) t))
                     (insert "[no discrepancies found]\n")
                   (insert
                    "\n\nThese files failed the verification. The characters
indicate the reason of the discrepancy:\n
5\tMD5 sum
S\tFile size
L\tSymlink
T\tMtime
D\tDevice
U\tUser
G\tGroup
M\tMode (includes permissions and file type)\n"))
                 (setq buffer-read-only nil))))
    (if (eq (length pkgs) 1)
        (setq rpm-package-name (car pkgs))
      (setq rpm-package-name nil))
    (setq buffer-read-only t)))

;; Note that I do not approve of using the -v option to display a
;; verbose listing of the files because that would display the details
;; as the rpm database reflects them - they could differ from the
;; files living in the filesystem. This can lead to great confusion if
;; the user is not aware of this.
;; The alternative would be to stat each file and then insert the
;; results but that would lead to the opposite confusion if one
;; expects the database data.
;; By only displaying the file names I hope that it is clear that a
;; file belongs (or once belonged) to a certain package but that it
;; might have changed (or even does not exist any more) in the
;; meantime.
(defun rpm-do-visit (package)
  "Visit package PACKAGE using rpm."

  (rpm-set-clear-buf package)
  (save-excursion
    (rpm-call-rpm-sync
     (append (list rpm-binary) rpm-opts-flist (list package)) nil))
  (setq rpm-package-name package)
  ;; Make the filenames look click-able
  (unless rpm-lemacs
    (save-excursion
      (goto-char (1- (point-max)))
      (let ((end (point)))
        (while (re-search-backward "^[/]"
                                   (save-excursion
                                     (beginning-of-line)
                                     (point))
                                   t)
          (progn
            (set-text-properties (point) end
                                 '(mouse-face highlight))
            (end-of-line 0)
            (setq end (point)))))))
  (setq buffer-read-only t))

;;
;; The interactive interface functions ....
;;

;;;###autoload
(defun rpm-dired-install (arg)
  "Install all marked (or next ARG) rpm-files."
  (interactive "P")

  (let ((files
         ;; this may move point if ARG is an integer
         (dired-map-over-marks (dired-get-filename) arg)))

    (if (dired-mark-pop-up
         " *Packages*" 'rpm-install files dired-deletion-confirmer
         (format "Install %s " (dired-mark-prompt arg files)))
        (rpm-do-install files))
    ))

(defun rpm-execute ()
  "Uninstall the packages flagged for deletion."
  (interactive)

  (when (string= (buffer-name) rpm-buf-index)
    (let* ((pkgs (rpm-marked 'to-be-deleted))
           (count (length pkgs)))
      (if (eq count 0)
          (message "Nothing to do...")
        (when (yes-or-no-p (format "Uninstall the %d marked packages? "
                                   count))
          (rpm-do-uninstall pkgs))))))

(defun rpm-locate-package (file)
  "Locate the package containing FILE."
  (interactive "fLocate package for file: ")

  (let (argv status)
    (rpm-set-clear-buf rpm-buf-temp)
    (setq argv (append (list rpm-binary)
                       rpm-opts-find-flist
                       (list (expand-file-name file))))
    (setq status (rpm-call-rpm-sync argv nil))
    (when (eq status 0)
      (let (pkg-name)
        (goto-char (point-min))
         (setq pkg-name (buffer-substring (point) (save-excursion
                                                   (end-of-line) (point))))
         (kill-buffer nil)
         (rpm-do-visit pkg-name)
          (save-excursion
            (when (re-search-forward (concat "^" file) (point-max))
              (setq buffer-read-only nil)
              (add-text-properties (match-beginning 0)
                                   (match-end 0)
                                   '(face underline))
              (setq buffer-read-only t)))))))

(defun rpm-interrupt ()
  "If active kill the current rpm background process."
  (interactive)

  (when rpm-proc
    (delete-process rpm-proc)))

(defun rpm-invert-sort ()
  "Invert the current sort order."
  (interactive)

  (if (string= (buffer-name) rpm-buf-index)
      (progn
        (setq rpm-reverse-sort (not rpm-reverse-sort))
        (rpm-sort-index))))

(defun rpm-install (package)
  "Install package PACKAGE."
  (interactive "fInstall package: ")

  (rpm-do-install (list package)))

(defun rpm-man ()
  "Show the man-page for the rpm utility."
  (interactive)

  (manual-entry "rpm"))

(defun rpm-mark (arg)
  "Mark the current (or next ARG) packages for subsequent commands."
  (interactive "p")

  (while (> arg 0)
    (let* ((tin (tin-locate rpm-crumb-box (point)))
           (cookie (tin-cookie rpm-crumb-box tin))
           (tag (assoc 'tag cookie)))
      (if tag
          (progn
            (setcdr tag 'marked)
            (tin-invalidate rpm-crumb-box tin)
            (tin-goto-next rpm-crumb-box (point) 1))))
    (setq arg (1- arg))))

(defun rpm-mark-delete (arg)
  "Mark the current (or next ARG) packages for subsequent deletion."
  (interactive "p")

  (while (> arg 0)
    (let* ((tin (tin-locate rpm-crumb-box (point)))
           (cookie (tin-cookie rpm-crumb-box tin))
           (tag (assoc 'tag cookie)))
      (if tag
          (progn
            (setq rpm-tag-d-size (+ rpm-tag-d-size
                                    (cdr (assoc 'size cookie))))
            (rpm-update-tag-string)
            (setcdr tag 'to-be-deleted)
            (tin-invalidate rpm-crumb-box tin)
            (tin-goto-next rpm-crumb-box (point) 1))))
    (setq arg (1- arg))))

(defun rpm-quit ()
  "Quit an rpm buffer.
Quitting the index buffer kills all rpm output buffers and
buries the index.  Quitting from an rpm output buffers kills it."
  (interactive)

  (if (string= (buffer-name) rpm-buf-index)
      ;; Kill all rpm buffers and bury the index
      (let (buffers)
        (if rpm-proc
            (error "Process rpm is still active in the background"))
        (setq buffers
              (delete
               nil
               (mapcar (function
                        (lambda (buf)
                          (if (eq (cdr (assoc 'major-mode
                                              (buffer-local-variables buf)))
                                  'rpm-output-mode)
                              buf
                            nil)))
                       (buffer-list))))
        (mapcar 'kill-buffer buffers)
        (bury-buffer))
    (kill-buffer nil)))

(defun rpm-rebuild-index ()
  "Rebuild the index."
  (interactive)

  (rpm-rebuild-crumb-box))

(defun rpm-requires ()
  "List all required packages for package(s)."
  (interactive)

  (if (string= (buffer-name) rpm-buf-index)
      (rpm-do-requires (rpm-build-arglist))
    (rpm-do-requires (list (rpm-visited-pkg)))))

(defun rpm-set-sort (sort-crit)
  "Set the sort criteria for the index list to SORT-CRIT."
  (interactive
   (list (completing-read "Sort criterion: "
                          '(("name" . 1)
                            ("size" . 2)
                            ("install-date" . 3))
                    nil t)))

  (setq rpm-sort-crit (intern sort-crit))
  (rpm-sort-index))

;; These are called from the menu
(defun rpm-set-sort-by-name ()
  "Sort the list by names."
  (interactive)
  (rpm-set-sort "name"))

(defun rpm-set-sort-by-size ()
  "Sort the list by size."
  (interactive)
  (rpm-set-sort "size"))

(defun rpm-set-sort-by-install-date ()
  "Sort the list by the installation date."
  (interactive)
  (rpm-set-sort "install-date"))

(defun rpm-toggle-format ()
  "Switch between default and alternate display format of the index."
  (interactive)

  (if (eq rpm-format-used 'rpm-index-format)
      (setq rpm-format-used 'rpm-alt-index-format)
    (setq rpm-format-used 'rpm-index-format))
  (message "Reformatting...")
  (let ((tin (tin-locate rpm-crumb-box (point))))
    (collection-refresh rpm-crumb-box)
    (tin-goto rpm-crumb-box tin))
  (message "Reformatting...Done"))

(defun rpm-unmark (arg)
  "Remove all marks from the current (or next ARG) packages."
  (interactive "p")

  (while (> arg 0)
    (let* ((tin (tin-locate rpm-crumb-box (point)))
           (cookie (tin-cookie rpm-crumb-box tin))
           (tag (assoc 'tag cookie)))
      (if (cdr tag)
          (progn
            (cond
             ((eq (cdr tag) 'to-be-deleted)
              (setq rpm-tag-d-size (- rpm-tag-d-size
                                      (cdr (assoc 'size cookie))))
              (rpm-update-tag-string)))
            (setcdr tag nil)
            (tin-invalidate rpm-crumb-box tin)
            (tin-goto-next rpm-crumb-box (point) 1))))
    (setq arg (1- arg))))

(defun rpm-unmark-all ()
  "Remove all marks from all packages."
  (interactive)

  (mapcar
   (function (lambda (tin)
               (let* ((cookie (tin-cookie rpm-crumb-box tin))
                      (tag (assoc 'tag cookie)))
                 (setcdr tag nil)
                 (tin-invalidate rpm-crumb-box tin))))
   (collection-collect-tin rpm-crumb-box
                           'rpm-is-marked))
  (setq rpm-tag-d-size 0)
  (rpm-update-tag-string))

(defun rpm-verify ()
  "Verify package(s) using rpm."
  (interactive)

  (if (string= (buffer-name) rpm-buf-index)
      (rpm-do-verify (rpm-build-arglist))
    (rpm-do-verify (list (rpm-visited-pkg)))))

(defun rpm-visit-mouse (event)
  "Call the visit command for the mouse event EVENT."
  (interactive "e")

  (let ((buffer (current-buffer)))
    (set-buffer (window-buffer (posn-window (event-end event))))
    (goto-char (posn-point (event-end event)))
    (rpm-visit)
    (set-buffer buffer)))

(defun rpm-visit ()
  "Visit package in current line or edit the file in the current line."
  (interactive)

  (if (string= (buffer-name) rpm-buf-index)
       ;; We are in the index
       (rpm-do-visit (rpm-package-at-pos (point)))
      ;; We are inside a package listing
      (let ((file (rpm-filename-at-point)))
        (if (eq (aref file 0) ?/)
            (find-file file)
          (error "There is no file on this line")))))

(defun rpm-view ()
  "Visit package in current line or view the file in the current line."
  (interactive)

  (if (string= (buffer-name) rpm-buf-index)
       ;; We are in the index
       (rpm-do-visit (rpm-package-at-pos (point)))
      ;; We are inside a package listing
      (let ((file (rpm-filename-at-point)))
        (if (eq (aref file 0) ?/)
            (view-file file)
          (error "There is no file on this line")))))

(provide 'rpm)

;;; rpm.el ends here
