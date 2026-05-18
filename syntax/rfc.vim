if exists("b:current_syntax")
  finish
endif

" ── Section headers at column 0 ──────────────────────────────────────────────

" Numeric: "1.  Introduction", "1.2.3.  Deep Section"
syn match RfcSectionHeader "^\d\+\(\.\d\+\)*\.*\s\{2,\}\S.*$"

" Appendix top-level: "Appendix A.  State Machine"
syn match RfcSectionHeader "^Appendix\s\+[A-Z][0-9.]*\.*\s\{2,\}\S.*$"

" Letter-based appendix sub-section: "A.1.  Client", "B.3.1.  Title"
syn match RfcSectionHeader "^[A-Z]\.\(\d\+\.\)\+\s\{2,\}\S.*$"

" ── Table-of-contents entries (indented, trailing dots + page number) ────────

" Numeric and letter-based: "   1.  Title ....  N" / "     A.1.  Title ....  N"
syn match RfcTocEntry "^\s\+\d\+\(\.\d\+\)*\.*\s\+[^.]\+\.\{3,\}\s*\d\+\s*$"
syn match RfcTocEntry "^\s\+[A-Z]\.\(\d\+\.\)*\s\+[^.]\+\.\{3,\}\s*\d\+\s*$"

" Named entries (no leading section number):
"   "   Authors' Addresses ....  N"
"   "   Appendix A.  State Machine ....  N"
"   "   References ....  N"
syn match RfcTocNamedEntry "^\s\+[A-Z][^0-9.].*\.\{3,\}\s*\d\+\s*$"

" ── References section ───────────────────────────────────────────────────────

" Reference labels: [RFC2104], [SSH-ARCH], [1]
syn match RfcRefLabel "\[.\{-1,\}\]"

" ── Inline elements ──────────────────────────────────────────────────────────

" Centered all-caps RFC title in the document header
syn match RfcTitle "^\s\+[A-Z][A-Z ]\{5,\}[A-Z]\s*$"

" RFC cross-references: RFC 791, RFC-791, rfc791
syn match RfcRef "\<[Rr][Ff][Cc][- ]\?\d\+"

" HTTP/HTTPS URLs
syn match RfcUrl "\<https\?://[^ \t\r\n>]*"

" ── Highlight links ──────────────────────────────────────────────────────────

hi def link RfcSectionHeader  Title
hi def link RfcTocEntry       Statement
hi def link RfcTocNamedEntry  Statement
hi def link RfcRefLabel       Special
hi def link RfcTitle          Special
hi def link RfcRef            Identifier
hi def link RfcUrl            Underlined

let b:current_syntax = "rfc"
