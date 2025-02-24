;;; ox-beamer-lecture.el --- Beamer Lecture Back-End for Org Export Engine -*- lexical-binding: t; -*-

;; Copyright (C) 2007-2024 Free Software Foundation, Inc.

;; Author: Felix J. Esser <code-esser@mailbox.org>
;; Maintainer: Felix J. Esser <code-esser@mailbox.org>
;; Created: 2025
;; Version: 1.0
;; Homepage: https://github.com/fjesser/ox-beamer-lecture
;; Keywords: org, text, tex

;;; Commentary:
;;
;; This library implements a special Beamer back-end to export an Org
;; buffer to a lecture series. It is derived from the Beamer backend
;; which is derived from the LaTeX one.

;;; Code:

(require 'ox-beamer)

;; Create special LaTeX beamer lecture class It uses format-spec templates for
;; the expansion of %h handout and %l lecture label within the
;; org-beamer-lecture-template function. Appendix is redefined because using
;; lectures only the first \appendix is respected.
(add-to-list 'org-latex-classes
             '("beamer-lecture"
               "\\documentclass[compress,ignorenonframetext%h]{beamer}
\\includeonlylecture{%l}
\\renewcommand<>{\\appendix}{\\part#1{\\appendixname}}"
               org-beamer-lecture--compute-headings))
;; Create class for beamer's article mode export
(add-to-list 'org-latex-classes
             '("beamer-lecture-article"
               "\\documentclass{report}
\\usepackage{beamerarticle}"
		       ("\\chapter{%s}" . "\\chapter*{%s}")
		       ("\\section{%s}" . "\\section*{%s}")
		       ("\\subsection{%s}" . "\\subsection*{%s}")
		       ("\\subsubsection{%s}" . "\\subsubsection*{%s}")))


;;; User-Configurable Variables

(defgroup org-export-beamer-lecture nil
  "Options specific for using beamer lecture in LaTeX export."
  :tag "Org Beamer Lecture"
  :group 'org-export
  :version "29.4")

(defgroup org-export-beamer-lecture-article nil
  "Options specific for using beamer lecture article in LaTeX export."
  :tag "Org Beamer Lecture Article"
  :group 'org-export-beamer-lecture
  :version "29.4")

(defcustom org-beamer-lecture-frame-level 3
  "The level at which headlines become frames.

The first level will be the `\\lecture' level, so the lowest
possible level is 2. See `org-beamer-frame-level' for more
information."
  :group 'org-export-beamer-lecture
  :type 'integer)

(defcustom org-beamer-lecture-list-default-overlay ""
  "Default overlay specification for level 1 list environments.

Includes `\\begin{environment}[<%s>]' for environments `itemize',
`enumerate', and `description'. This means do not include any
brackets in this string. If you want to uncover default overlay
specification for nested lists, use the LaTeX Beamer command
`\\setbeamertemplate{itemize/enumerate subbody begin}
{\\beamerdefaultoverlayspecification{<.->}}'"
  :group 'org-export-beamer-lecture
  :type 'string)

(defcustom org-beamer-lecture-require-lecture t
  "Whether to prompt for a lecture number during slides export.

If this variable is nil, all lectures will always be compiled
automatically."
  :group 'org-export-beamer-lecture
  :type 'boolean)

(defcustom org-beamer-lecture-label "lecture"
  "Default string used for lecture label.

It is used when exporting to LaTeX beamer lecture in
`\\lecture{label}{title}' and is thus used for the folder name
and file name creation when exporting to slides. It can be set
with the in-buffer setting `#+BEAMER_LECTURE_LABEL'."
  :group 'org-export-beamer-lecture
  :type 'string)

(defcustom org-beamer-lecture-beamer-suffix "-beamer"
  "Suffix for beamer presentation files.

Beamer presentation files contain overlays and maybe notes. It
has the form `labelXX-title/prefix-title-suffix.tex' where XX is
a number. See also `org-beamer-lecture-label' and `'."
  :group 'org-export-beamer-lecture
  :type 'string)

(defcustom org-beamer-lecture-handout-suffix nil
  "Suffix for handout files.

Handout files do not contain overlays nor notes. It has the form
`labelxx-title/prefix-title-suffix.tex'. See also
`org-beamer-lecture-label' and
`org-beamer-lecture-beamer-suffix'."
  :group 'org-export-beamer-lecture
  :type 'string)

(defcustom org-beamer-lecture-article-suffix "-article"
  "Suffix for files of article export."
  :group 'org-export-beamer-lecture
  :type 'string)

(defcustom org-beamer-lecture-article-rename-chapter t
  "Whether to rename the chaptername for article mode export.

If t, `\\renrewcommand{\\chaptername}{label}' will be inserted
into the header and label will depend on
`org-beamer-lecture-article-label.'

If nil, no `\\renrewcommand{\\chaptername}{label}' will be
included during export.

It can be set with the in-buffer options setting `#+OPTIONS:
rch:nil'."
  :group 'org-export-beamer-lecture-article
  :type 'boolean)

(defcustom org-beamer-lecture-article-label nil
  "Default string used for lecture label in article mode.

It is used for the chapter name in article mode. If nil, the
value is the same as `org-beamer-lecture-label' but capitalized.
It can be set with the in-buffer setting
`#+BEAMER_LECTURE_ARTICLE_LABEL'."
  :group 'org-export-beamer-lecture-article
  :type 'string)

(defcustom org-beamer-lecture-article-dir "article"
  "Folder in which the article mode version is saved."
  :group 'org-export-beamer-lecture-article
  :type 'string)

(defcustom org-beamer-lecture-article-exclude-tag "noarticle"
  "Tag that marks trees to be excluded from export to article mode.

This makes it possible to use Beamer's article mode functionality
and also exclude certain trees (e.g., introductory lecture) from
article mode. This tag will be added to `org-export-exclude-tags'
for the time of the export."
  :group 'org-export-beamer-lecture-article
  :type 'string)


;;; Internal Variables

(defvar org-beamer-lecture--compile-handout t
  "Whether to compile the beamer handout file.

This variable is set to nil in the fast export functions.")

(defvar-local org-beamer-lecture--dates nil
  "List to capture dates.

The variable will be populated with dates located in EXPORT_DATES
properties of Level 1 Headings used to provide the correct date
for each lecture.")

(defvar org-beamer-lecture--lecture-number 0
  "Set during export to determine which lecture(s) should be exported.")
 
(defvar org-beamer-lecture--to-compile nil
  "List for to tex files to compile.

The variable will be populated with beamer and handout tex files
which should be compiled.")


;;; Internal Functions

(defun org-beamer-lecture--article-file (subtreep)
  "Return the output file name when exporting to article mode.

This function is a wrapper around `org-export-output-file-name'.
Depending on the value of `org-beamer-lecture-article-dir' the
file is exported into and compiled in the specified folder.

SUBTREEP is forwarded to `org-export-output-file-name'.'"
  (let ((full-suffix (concat org-beamer-lecture-article-suffix ".tex")))
    (if org-beamer-lecture-article-dir
        (progn
          (unless (file-directory-p org-beamer-lecture-article-dir)
            (make-directory org-beamer-lecture-article-dir))
          (file-name-concat org-beamer-lecture-article-dir
                            (org-export-output-file-name full-suffix subtreep)))
      (org-export-output-file-name full-suffix subtreep))))

(defun org-beamer-lecture--compute-headings (lvl numbered)
  "Compute LaTeX beamer lecture headings.

The headings are computed based on the specified heading
LEVEL (LVL) and whether the headings should be NUMBERED. It is
used for the custom LaTeX class beamer-lecture and
beamer-lecture-article in `org-latex-classes'. It uses
`org-beamer-lecture-label' for the lecture labels.

LEVEL:
  1: Lecture
  2: Section
  3: Subsection
  4: Subsubsection

NUMBERED:
  If non-nil, headings are numbered; otherwise, they are unnumbered.

The function generates LaTeX Beamer-compatible heading strings using the
given level and numbering preference. It also maintains an internal counter
for lecture numbering (when the level is 1)."
  ;; Define buffer-local var if not set
  (unless (boundp 'org-beamer-lecture--number)
    (setq-local org-beamer-lecture--number 0))
  ;; Code to execute
  (cond ((= lvl 1) (progn
                     (setq-local org-beamer-lecture--number (1+ org-beamer-lecture--number))
                     (concat "\\lecture{%s}{"
                             org-beamer-lecture-label
                             (format "%02d" org-beamer-lecture--number)
                             "}")))
        ((= lvl 2) (if numbered
                       "\\section{%s}"
                     "\\section*{%s}"))
        ((= lvl 3) (if numbered
                       "\\subsection{%s}"
                     "\\subsection*{%s}"))
        ((= lvl 4) (if numbered
                       "\\subsubsection{%s}"
                     "\\subsubsection*{%s}"))))

(defun org-beamer-lecture--extract-lecture (contents)
  "Extract the content in all `\\lecture{title}{label}' occurrences.
CONTENTS is the transcoded string by org export.
Outputs an alist of `(label . title)' pairs."
  (let ((lecture-labels))
    (with-temp-buffer
      (insert contents)
      (goto-char (point-min))
      (while (re-search-forward "\\\\lecture.*?{" nil t) ; Find \lecture[]{
        (let ((title (buffer-substring-no-properties
                      (point)
                      ;; Get point before } , Start scan before {
                      (1- (scan-lists (1- (point)) 1 0)))))
          (goto-char (scan-lists (1- (point)) 1 0)) ; Move past first arg
          (let ((label (buffer-substring-no-properties
                        (1+ (point))
                        (1- (scan-lists (point) 1 0)))))
            (push `(,label . ,title) lecture-labels)))))
    (nreverse lecture-labels)))

(defun org-beamer-lecture--prompt-lecture ()
  "Prompt for lecture to process.

This function is used in the export functions."
  (if (not org-beamer-lecture-require-lecture)
      0
    (read-number "Number of lecture to process (0 for all): ")))

(defun org-beamer-lecture-remove-latex (string)
  "Remove LaTeX code from a STRING and strip whitespace.

First, remove LaTeX commands without the braces, then remove the
braces with their content, and lastly remove leading and trailing
whitespace."
  (let ((replacements
        '(("\\\\\\w+" . "")
          ("{[^}]*}" . "")
          ("^[[:space:]]*\\(.*?\\)[[:space:]]*$" . "\\1"))))
    (seq-reduce '(lambda (string replacement-pair)
                   (replace-regexp-in-string
                    (car replacement-pair)
                    (cdr replacement-pair)
                    string))
                replacements
                string)))

(defun org-beamer-lecture--transform-title (title)
  "Transform TITLE string to directory name.

Steps
1) Remove LaTeX code and strip whitespace
2) Replace Roman numerals with numbers at the end of the string
3) Replace dashes surrounded by whitespace with dash
4) Replace whitespace with dash
5) Downcase all characters"
  (let ((replacements                   ; Order of replacements matters
         '(("III$" . "3") ("II$" . "2") ("I$" . "1")
           ("IV$". "4") ("V$" . "5" )
           ("[[:space:]]+-+[[:space:]]+" . "-")
           ("[[:space:]]+" . "-"))))
    (downcase
     (seq-reduce '(lambda (title replacement-pair)
                     (replace-regexp-in-string
                      (car replacement-pair)
                      (cdr replacement-pair)
                      title))
                 replacements
                 (org-beamer-lecture-remove-latex title)))))

(defun org-beamer-lecture--compile (_body-texfile &optional snippet)
  "Compile Beamer Lecture TeX files.

BODY-TEXFILE is the name of the body texfile but is ignored
because multiple tex files are compiled which are stored in the
variable `org-beamer-lecture--to-compile'. This variable is
populated in `org-beamer-lecture-template'.

When optional argument SNIPPET is non-nil, TEXFILE is a temporary
file used to preview a LaTeX snippet.  In this case, do not
create a log buffer and do not remove log files.

Return PDF file name of the last beamer presentation file that
was compiled or raise an error if it couldn't be produced."
  (let ((outpdf))
    (dolist (tex org-beamer-lecture--to-compile)
      (setq outpdf (org-latex-compile (car tex) snippet))
      (when org-beamer-lecture--compile-handout
        (org-latex-compile (cadr tex) snippet)))
    ;; Return presentation file to open it
    outpdf))


;;; Define Backends

;; Export backend for slides: beamer and handout
(org-export-define-derived-backend 'beamer-lecture 'beamer
  :menu-entry
  '(?L "Export to LaTeX Beamer Lecture"
       ((?L "As lecture buffer"
            org-beamer-lecture-export-as-latex)
        (?l "As lecture LaTeX files"
            org-beamer-lecture-export-to-latexs)
        (?p "As lecture PDF files"
            org-beamer-lecture-export-to-pdfs)
        (?o "As lecture PDF files and open beamer PDF"
            (lambda (a s v b)
              (if a (org-beamer-lecture-export-to-pdfs t s v b)
                (org-open-file (org-beamer-lecture-export-to-pdfs nil s v b)))))
        (?f "As beamer PDF file - fast"
            org-beamer-lecture-export-to-pdf-fast)
        (?F "As beamer PDF and open - fast"
            (lambda (a s v b)
              (if a (org-beamer-lecture-export-to-pdf-fast t s v b)
                (org-open-file (org-beamer-lecture-export-to-pdf-fast nil s v b)))))))
  :options-alist
  '(;; (1) property, (2) keyword, (3) #+OPTIONS string,
    ;; (4) default value, (5) how to handle multiple keywords
    ;; --- General Export Settings
    ;; --- LaTeX Export Settings
    (:latex-class "LATEX_CLASS" nil "beamer-lecture" nil)
    ;; --- Beamer Export Settings
    (:headline-levels nil "H" org-beamer-lecture-frame-level)
    ;; --- Beamer Lecture Export Settings
    (:beamer-lecture-label "BEAMER_LECTURE_LABEL" nil org-beamer-lecture-label))
  :translate-alist
  '((headline . org-beamer-lecture-headline)
    (plain-list . org-beamer-lecture-plain-list)
    (template . org-beamer-lecture-template)))

;; Extra backend for article mode
(org-export-define-derived-backend 'beamer-lecture-article 'beamer
  :menu-entry
  '(?L 2 ((?A "As article buffer"
              org-beamer-lecture-export-article-as-latex)
          (?a "As article LaTeX file"
              org-beamer-lecture-export-article-to-latex)
          (?P "As article PDF file"
              org-beamer-lecture-export-article-to-pdf)
          (?O "As article PDF and open"
              (lambda (a s v b)
                (if a (org-beamer-lecture-export-article-to-pdf t s v b)
                  (org-open-file (org-beamer-lecture-export-article-to-pdf nil s v b)))))))
  :options-alist
  '(;; (1) property, (2) keyword, (3) #+OPTIONS string,
    ;; (4) default value, (5) how to handle multiple keywords
    ;; --- General Export Settings
    ;; --- LaTeX Export Settings
    (:latex-class "LATEX_CLASS" nil "beamer-lecture-article" nil)
    ;; --- Beamer Lecture Article Export Settings
    (:beamer-lecture-label "BEAMER_LECTURE_LABEL" nil org-beamer-lecture-label)
    (:beamer-lecture-article-rename-chapter nil "rch" org-beamer-lecture-article-rename-chapter)
    (:beamer-lecture-article-label "BEAMER_LECTURE_ARTICLE_LABEL" nil
                                   org-beamer-lecture-article-label))
  :translate-alist
  '((plain-list . org-beamer-lecture-plain-list)
    (template . org-beamer-lecture-article-template)))


;;; Transcode Functions

;;;; Headline
(defun org-beamer-lecture-headline (headline contents info)
  "Transcode HEADLINE element into Beamer lecture code.
CONTENTS is the contents of the headline. INFO is a plist used as
a communication channel.

In addition to `org-beamer-headline', this function defines the
beamer-lecture-label and extracts the EXPORT_DATES of the Level 1
headings during export."
  (unless (org-element-property :footnote-section-p headline)
    (let ((level (org-export-get-relative-level headline info))
	      (frame-level (org-beamer--frame-level headline info))
	      (environment (let ((env (org-element-property :BEAMER_ENV headline)))
			             (or (org-string-nw-p env) "block")))
          ;; Define label for org-beamer-lecture--compute-headings
          ;; No other place possible to define so it works
          (org-beamer-lecture-label (plist-get info :beamer-lecture-label)))
      ;; Extract date and convert to timestamp if possible
      (when (= level 1)
        (let* ((lecture-date (org-element-property :EXPORT_DATE headline))
               (lecture-ts (org-timestamp-from-string lecture-date)))
          (setq-local org-beamer-lecture--dates
                      (append org-beamer-lecture--dates
                              `(,(or lecture-ts lecture-date))))))
      ;; org-beamer code
      (cond
       ;; Case 1: Resume frame specified by "BEAMER_ref" property.
       ((equal environment "againframe")
	    (let ((ref (org-element-property :BEAMER_REF headline)))
	      ;; Reference to frame being resumed is mandatory.  Ignore
	      ;; the whole headline if it isn't provided.
	      (when (org-string-nw-p ref)
	        (concat "\\againframe"
		            ;; Overlay specification.
		            (let ((overlay (org-element-property :BEAMER_ACT headline)))
		              (when overlay
			            (org-beamer--normalize-argument
			             overlay
			             (if (string-match "\\`\\[.*\\]\\'" overlay) 'defaction
			               'action))))
		            ;; Options.
		            (let ((options (org-element-property :BEAMER_OPT headline)))
		              (when options
			            (org-beamer--normalize-argument options 'option)))
		            ;; Resolve reference provided by "BEAMER_ref"
		            ;; property.  This is done by building a minimal
		            ;; fake link and calling the appropriate resolve
		            ;; function, depending on the reference syntax.
		            (let ((target
			               (if (string-match "\\`\\(id:\\|#\\)" ref)
			                   (org-export-resolve-id-link
				                `(link (:path ,(substring ref (match-end 0))))
				                info)
			                 (org-export-resolve-fuzzy-link
			                  `(link (:path
				                      ;; Look for headlines only.
				                      ,(if (eq (string-to-char ref) ?*) ref
					                     (concat "*" ref))))
			                  info))))
		              ;; Now use user-defined label provided in TARGET
		              ;; headline, or fallback to standard one.
		              (format "{%s}" (org-beamer--get-label target info)))))))
       ;; Case 2: Creation of an appendix is requested.
       ((equal environment "appendix")
	    (concat "\\appendix"
		        (org-element-property :BEAMER_ACT headline)
		        "\n"
		        (make-string (org-element-property :pre-blank headline) ?\n)
		        contents))
       ;; Case 3: Ignore heading.
       ((equal environment "ignoreheading")
	    (concat (make-string (org-element-property :pre-blank headline) ?\n)
		        contents))
       ;; Case 4: HEADLINE is a note.
       ((member environment '("note" "noteNH"))
        (concat "\\note"
		        ;; Overlay specification.
		        (let ((overlay (org-element-property :BEAMER_ACT headline)))
		          (when overlay
		            (org-beamer--normalize-argument
		             overlay
		             (if (string-match "\\`\\[.*\\]\\'" overlay)
			             'defaction 'action))))
		        (format "{%s}"
                        (concat (and (equal environment "note")
                                     (concat
                                      (org-export-data
                                       (org-element-property :title headline)
				                       info)
                                      "\n"))
				                (org-trim contents)))))
       ;; Case 5: HEADLINE is a frame.
       ((= level frame-level)
	    (org-beamer--format-frame headline contents info))
       ;; Case 6: Regular section, extracted from
       ;; `org-latex-classes'.
       ((< level frame-level)
	    (org-beamer--format-section headline contents info))
       ;; Case 7: Otherwise, HEADLINE is a block.
       (t (org-beamer--format-block headline contents info))))))


;;;; Plain List
;; Redefine org-beamer-plain-list
;; Provides default overlay specification (+-) for all lists
;; However, can be overwritten with e.g., #+ATTR_BEAMER: :overlay <1->
;; before list. Only one line is changed to orig function.
(defun org-beamer-lecture-plain-list (plain-list contents info)
  "Transcode a PLAIN-LIST element into Beamer code.
CONTENTS is the contents of the list.  INFO is a plist holding
contextual information.

Is based on `org-beamer-plain-list' but specifies a default
overlay specification which is <+->."
  (let* ((type (org-element-property :type plain-list))
	 (attributes (org-combine-plists
		      (org-export-read-attribute :attr_latex plain-list)
		      (org-export-read-attribute :attr_beamer plain-list)))
	 (latex-type (let ((env (plist-get attributes :environment)))
		       (cond (env)
			     ((eq type 'ordered) "enumerate")
			     ((eq type 'descriptive) "description")
			     (t "itemize")))))
    (org-latex--wrap-label
     plain-list
     (format "\\begin{%s}%s%s\n%s\\end{%s}"
	     latex-type
	     ;; Default overlay specification, if any.
	     (org-beamer--normalize-argument
          ; Following line is only line that changed!!! Was: ""
	      (or (plist-get attributes :overlay) org-beamer-lecture-list-default-overlay)
	      'defaction)
	     ;; Second optional argument depends on the list type.
	     (org-beamer--normalize-argument
	      (or (plist-get attributes :options) "")
	      'option)
	     ;; Eventually insert contents and close environment.
	     contents
	     latex-type)
     info)))

;;;; Template
(defun org-beamer-lecture-template (contents info)
  "Return document string after Beamer conversion.

It returns only the string within the `\begin{document}' and
`\end{document}' environment which is exported to the body
document. As a side effect, it creates the folder for the beamer
and handout slides as well as the templates for those files.
Additionally, it records the beamer and handout files which need
to be compiled by the function `org-beamer-lecture--compile'.

CONTENTS is the transcoded contents string. INFO is a
plist holding export options.

This function is only called when body-only is non-nil or there
is no template available."
  ;; Error when suffixes are the same and it creates the same file
  (when (equal org-beamer-lecture-beamer-suffix
               org-beamer-lecture-handout-suffix)
    (error "The variables org-beamer-lecture-<beamer|handout>-suffix have the same value: %s"
           org-beamer-lecture-beamer-suffix))
  ;; Process presentation content
  (let ((lecture-labels (org-beamer-lecture--extract-lecture contents))
        ;; Change title command because of ignorenonframetext option
        (org-latex-title-command "\\begin{frame}\n\\maketitle\\end{frame}")
        (index 0)) ; Index for while loop
    ;; Check whether input number is allowed
    (when (or (< org-beamer-lecture--lecture-number 0)
              (> org-beamer-lecture--lecture-number (length lecture-labels)))
      (error "Lecture number %s does not exist" org-beamer-lecture--lecture-number))
    ;; Loop over selected lectures
    (while (< index (length lecture-labels))
      (let* ((lecture (nth index lecture-labels))
             (label (car lecture))
             (title (org-beamer-lecture--transform-title (cdr lecture))))
        (when (or (= org-beamer-lecture--lecture-number 0)
                  (= (1- org-beamer-lecture--lecture-number) index))
          ;; Use EXPORT_DATE property of lecture
          (plist-put info :date `(,(nth index org-beamer-lecture--dates)))
          ;; Create and process tex files
          (let* ((outdir (concat label "-" title))
                 (base-outfile (file-name-concat outdir outdir))
                 (beamer-texfile (concat base-outfile
                                         org-beamer-lecture-beamer-suffix
                                         ".tex") )
                 (handout-texfile (concat base-outfile
                                          org-beamer-lecture-handout-suffix
                                          ".tex"))
                 (slides-body (format "\\mode<all>{\\input{../%s}}\n\n"
                                      (plist-get info :output-file)))
                 ;; Logic taken from org-export-as
                 (tex-template (if (plist-get info :with-cite-processors)
                                   (org-cite-finalize-export
                                    (org-beamer-template slides-body info)
                                    info)
                                 (org-beamer-template slides-body info))))
            ;; Create directory
            (unless (file-directory-p outdir)
              (make-directory outdir))
            ;; Create beamer tex file
            ;; (format) throws error with LaTeX comments. Use (format-spec)
            ;; with ignore-missing
            (with-temp-file beamer-texfile
              (insert (format-spec tex-template
                                   `((?h . "")
                                     (?l . ,label))
                                   t)))
            ;; Create handout tex file
            (with-temp-file handout-texfile
              (insert (format-spec tex-template
                                   `((?h . ",handout")
                                     (?l . ,label))
                                   t)))
            ;; Add tex files to list for org-beamer-lecture-compil
            (push `(,beamer-texfile ,handout-texfile)
                  org-beamer-lecture--to-compile))))
      (setq index (1+ index)))
    ;; Correct order of lectures to compile
    (setq org-beamer-lecture--to-compile
          (nreverse org-beamer-lecture--to-compile)))
  ;; Only output contents, previous code is for side effects
  (concat
   (when (plist-get info :time-stamp-file)
     (format-time-string "%% Created %Y-%m-%d %a %H:%M by org-beamer-lecture.el\n"))
   contents))

;;;; Template - Article
(defun org-beamer-lecture-article-template (contents info)
  "Return document string after Beamer conversion.

In addition to `org-beamer-template', it defines the label which
is included in the Beamer Lecture Article class string, if it
should be exported.

CONTENTS is the transcoded contents string. INFO is a
plist holding export options."
  (when (plist-get info :beamer-lecture-article-rename-chapter)
    (let* ((article-label (plist-get info :beamer-lecture-article-label))
           (lecture-label (plist-get info :beamer-lecture-label))
           (chapterlabel (cond (article-label article-label)
                               (lecture-label (capitalize lecture-label))
                               (t "Chapter")))
           (renewcommand (concat "\\renewcommand{\\chaptername}{"
                                 chapterlabel "}")))
      (plist-put info :beamer-header
                 (string-join
                  (delq nil `(,(plist-get info :beamer-header)
                              ,renewcommand))
                  "\n"))))
  (plist-put info :file (concat "article/"
                                (plist-get info :file)))
  (org-beamer-template contents info))


;;; Commands

;;;###autoload
(defun org-beamer-lecture-export-as-latex
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer as body of Beamer Lecture buffer.
If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting buffer should be accessible
through the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

The optional argument BODY-ONLY does not have any effect. Only
the body is exported because the code outside
\"\\begin{document}\" and \"\\end{document}\" is by design
included in other files.

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Export is done in a buffer named \"*Org BEAMER Export*\", which
will be displayed when `org-export-show-temporary-export-buffer'
is non-nil."
  (interactive)
  (org-export-to-buffer 'beamer-lecture "*Org BEAMER LECTURE Export*"
    async subtreep visible-only body-only ext-plist (lambda () (LaTeX-mode))))

;;;###autoload
(defun org-beamer-lecture-export-to-latexs
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer as a Beamer Lecture presentations (tex files).

The user is prompted for the lecture number which creates the
corresponding folder with the beamer and handout slides. Entering
0 creates all possible folders and files.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting file should be accessible through
the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between \"\\begin{document}\" and \"\\end{document}\". In this
case no folder and files will be created, only the texfile
containing the document's body will be created.

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Return output file's name."
  (interactive)
  (let ((file (org-export-output-file-name ".tex" subtreep))
        (org-beamer-lecture--lecture-number
         (org-beamer-lecture--prompt-lecture))
        (org-beamer-lecture--to-compile nil))
    (org-export-to-file 'beamer-lecture file
      async subtreep visible-only body-only ext-plist)))

;;;###autoload
(defun org-beamer-lecture-export-to-pdfs
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer as a Beamer Lecture presentations (PDFs).

The user is prompted for the lecture number which creates the
corresponding folder with the beamer and handout slides. Entering
0 creates all possible folders and files.

If narrowing is active in the current buffer, only export its narrowed
    part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
    asynchronously.  The resulting file should be accessible through
    the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree at
    point, extracting information from the headline properties first.

When optional argument VISIBLE-ONLY is non-nil, don't export contents
    of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code between
    \"\\begin{document}\" and \"\\end{document}\".

EXT-PLIST, when provided, is a property list with external parameters
    overriding Org default settings, but still inferior to file-local
    settings.

Return Beamer Presentation PDF file's name."
  (interactive)
  (let ((file (org-export-output-file-name ".tex" subtreep))
        (org-beamer-lecture--lecture-number
         (org-beamer-lecture--prompt-lecture))
        (org-beamer-lecture--to-compile nil))
    (org-export-to-file 'beamer-lecture file
      async subtreep visible-only body-only ext-plist
      #'org-beamer-lecture--compile)))

;;;###autoload
(defun org-beamer-lecture-export-to-pdf-fast
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer as a Beamer Lecture beamer presentation (PDFs).

The user is prompted for the lecture number which creates the
corresponding folder with the beamer and handout slides. Entering
0 creates all possible folders and files. In comparison to
`org-beamer-lecture-export-to-pdfs', this export is faster.
First, it creates only the beamer slides and omits the handout
slides. Second, the export is disabled for `#+INCLUDE' keywords
as well as source code blocks. Third, `pdflatex' is used as the
compiler to compile the file only once.

If narrowing is active in the current buffer, only export its narrowed
    part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
    asynchronously.  The resulting file should be accessible through
    the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree at
    point, extracting information from the headline properties first.

When optional argument VISIBLE-ONLY is non-nil, don't export contents
    of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code between
    \"\\begin{document}\" and \"\\end{document}\".

EXT-PLIST, when provided, is a property list with external parameters
    overriding Org default settings, but still inferior to file-local
    settings.

Return Beamer Presentation PDF file's name.

Export current buffer to Beamer Lecture PDF in a fast way.
TODO: doc, uses only one run of pdflatex
To speed up the export process the inclusion of #+INCLUDE
keywords and the Org Babel code chunks is disabled.  It requires that
`org-beamer-lecture-export-to-pdfs' was run before. Optional
arguments ASYNC, SUBTREEP, VISIBLE-ONLY, BODY-ONLY, and EXT-PLIST
are passed to `org-export-to-file' (see its documentation for
details)."
  (interactive)
  (cl-letf ((file (org-export-output-file-name ".tex" subtreep))
            ;; Redefine functions for faster export
            ;; Do not expand #+INCLUDE keywords:
            ;; Is done regardless of C-v visibility export setting
            ((symbol-function 'org-export-expand-include-keyword)
             (lambda (&optional _a _b _c _d _e) nil))
            ;; Do not process code blocks
            (org-export-use-babel nil)
            (org-latex-pdf-process
             '("pdflatex -interaction=nonstopmode -output-directory=%o %f"))
            (org-beamer-lecture--lecture-number
             (org-beamer-lecture--prompt-lecture))
            (org-beamer-lecture--to-compile t)
            (org-beamer-lecture--compile-handout nil))
    (org-export-to-file 'beamer-lecture file
      ;; t = Export body only
      async subtreep visible-only body-only ext-plist
      #'org-beamer-lecture--compile)))

;;;###autoload
(defun org-beamer-lecture-export-article-as-latex
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer as Beamer Lecture buffer in Beamer's article mode.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting buffer should be accessible
through the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between `\begin{document}' and `\end{document}'.

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Export is done in a buffer named \"*Org BEAMER Export*\", which
will be displayed when `org-export-show-temporary-export-buffer'
is non-nil."
  (interactive)
  (let ((org-export-exclude-tags (cons org-beamer-lecture-article-exclude-tag
                                       org-export-exclude-tags)))
    (org-export-to-buffer 'beamer-lecture-article
        "*Org BEAMER LECTURE Article Export*"
      async subtreep visible-only body-only ext-plist
      (lambda () (LaTeX-mode)))))

;;;###autoload
(defun org-beamer-lecture-export-article-to-latex
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer as a Beamer Lecture article (tex).

The export uses beamer's article mode. Trees with a tag set in
`org-beamer-lecture-article-exclude-tag' will be ignored in
addition to `org-export-exclude-tags'. The file will be exported
to the folder specified in `org-beamer-lecture-article-dir'.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting file should be accessible through
the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between \"\\begin{document}\" and \"\\end{document}\".

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Return output file's name."
  (interactive)
  (let ((file (org-beamer-lecture--article-file subtreep))
        (org-export-exclude-tags (cons org-beamer-lecture-article-exclude-tag
                                       org-export-exclude-tags)))
    (org-export-to-file 'beamer-lecture-article file
      async subtreep visible-only body-only ext-plist)))

;;;###autoload
(defun org-beamer-lecture-export-article-to-pdf
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer as a Beamer Lecture article (PDF).

The export uses beamer's article mode. Trees with a tag set in
`org-beamer-lecture-article-exclude-tag' will be ignored in
addition to `org-export-exclude-tags'. The file will be exported
to the folder specified in `org-beamer-lecture-article-dir'.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting file should be accessible through
the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between \"\\begin{document}\" and \"\\end{document}\".

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Return output file's name."
  (interactive)
  (let ((file (org-beamer-lecture--article-file subtreep))
        (org-export-exclude-tags (cons org-beamer-lecture-article-exclude-tag
                                       org-export-exclude-tags)))
    (org-export-to-file 'beamer-lecture-article file
      async subtreep visible-only body-only ext-plist #'org-latex-compile)))

(provide 'ox-beamer-lecture)
;;; ox-beamer-lecture.el ends here

