if exists("b:current_syntax")
  finish
endif

" Section headers at column 0: "1.  Introduction", "1.2.3.  Deep Section"
syn match RfcSectionHeader "^\d\+\(\.\d\+\)*\.*\s\{2,\}\S.*$"

" TOC entries: indented, section number, title, trailing dots, page number
" e.g. "   1.  Introduction ............  1"
syn match RfcTocEntry "^\s\+\d\+\(\.\d\+\)*\.*\s\+[^.]\+\.\{3,\}\s*\d\+\s*$"

" Centered all-caps RFC title in the document header
" e.g. "                          INTERNET PROTOCOL"
syn match RfcTitle "^\s\+[A-Z][A-Z ]\{5,\}[A-Z]\s*$"

" RFC cross-references in body text: RFC 791, RFC-791, rfc791
syn match RfcRef "\<[Rr][Ff][Cc][- ]\?\d\+"

" HTTP/HTTPS URLs
syn match RfcUrl "\<https\?://[^ \t\r\n>]*"

hi def link RfcSectionHeader Title
hi def link RfcTocEntry Statement
hi def link RfcTitle Special
hi def link RfcRef Identifier
hi def link RfcUrl Underlined

let b:current_syntax = "rfc"
