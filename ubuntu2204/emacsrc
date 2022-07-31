;;
;; .emacs
;;

;;disable splash screen and startup message
(setq inhibit-startup-message t) 
(setq initial-scratch-message nil)

;; ESC SPACE is set-mark-command
(define-key global-map "\M- " 'set-mark-command)

;; Japanese Settings
(set-language-environment "Japanese")
(prefer-coding-system  'utf-8-unix)
(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)
(set-buffer-file-coding-system 'utf-8)
(setq default-buffer-file-coding-system 'utf-8)
(set-default-coding-systems 'utf-8)
(setq file-name-coding-system 'utf-8)

;; タブにスペースを使用する
(setq-default tab-width 4 indent-tabs-mode nil)

;; 改行コードを表示する
(setq eol-mnemonic-dos "(CRLF)")
(setq eol-mnemonic-mac "(CR)")
(setq eol-mnemonic-unix "(LF)")

;; シフト＋矢印で範囲選択
;;(setq pc-select-selection-keys-only t)
;;(pc-selection-mode 1)

;;; uncomment this line to disable loading of "default.el" at startup
;; (setq inhibit-default-init t)

;; turn on font-lock mode
;(when (fboundp 'global-font-lock-mode)
;  (global-font-lock-mode t))

;; enable visual feedback on selections
;(setq transient-mark-mode t)

;; default to better frame titles
;(setq frame-title-format
;      (concat  "%b - emacs@" (system-name)))

;; default to unified diffs
(setq diff-switches "-u")

;; always end a file with a newline
;(setq require-final-newline 'query)

;; do not create backup file
(setq backup-inhibited t)

;; delete auto-save file on exit
(setq delete-auto-save-files t)

;; display cursor column
(column-number-mode t)

;; display cursor line
(line-number-mode t)

;; set scroll line to 1
(setq scroll-step 1)

;; display time into mode line
(display-time)

