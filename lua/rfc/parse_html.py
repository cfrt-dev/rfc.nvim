#!/usr/bin/env python3
"""Parse RFC HTML into plain text + link/anchor map, output as JSON."""
import sys, json, re
from html.parser import HTMLParser

BLOCK = frozenset({
    'p', 'div', 'section', 'article', 'blockquote',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'li', 'dt', 'dd', 'tr', 'table', 'thead', 'tbody', 'tfoot',
    'ul', 'ol', 'dl', 'figure', 'figcaption',
    'header', 'footer', 'nav', 'aside', 'main',
})
SKIP = frozenset({'script', 'style', 'noscript', 'head'})


class RFCParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out   = []   # completed lines (str)
        self.cur   = ''   # line being assembled
        self.links = []   # [{line, col_start, col_end, href}]
        self.anch  = {}   # {id: line_number}  (0-based)
        self.stk   = []   # link stack: [{href, line, col}]
        self.skip  = 0    # depth inside SKIP elements
        self.pre   = 0    # depth inside <pre>

    def _nl(self):
        self.out.append(self.cur)
        self.cur = ''

    def _enl(self):
        if self.cur:
            self._nl()

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        ad  = dict(attrs)

        aid = ad.get('id') or ad.get('name')
        if aid:
            self.anch[aid] = len(self.out)  # record before flush so heading text lands here
            self._enl()

        if tag in SKIP:
            self.skip += 1
            return
        if self.skip:
            return

        if tag == 'pre':
            self._enl()
            self.pre += 1
        elif tag == 'br':
            self._nl()
        elif tag in BLOCK:
            self._enl()

        if tag == 'a':
            href = ad.get('href', '')
            if href:
                self.stk.append({'href': href, 'line': len(self.out), 'col': len(self.cur)})

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag in SKIP:
            self.skip = max(0, self.skip - 1)
            return
        if self.skip:
            return

        if tag == 'pre':
            self.pre = max(0, self.pre - 1)
            self._enl()
        elif tag in BLOCK:
            self._enl()

        if tag == 'a' and self.stk:
            lnk     = self.stk.pop()
            el, ec  = len(self.out), len(self.cur)
            if el == lnk['line']:
                ce = ec
            elif lnk['line'] < len(self.out):
                ce = len(self.out[lnk['line']])
            else:
                ce = lnk['col']
            if ce > lnk['col'] or el > lnk['line']:
                self.links.append({
                    'line':      lnk['line'],
                    'col_start': lnk['col'],
                    'col_end':   ce,
                    'href':      lnk['href'],
                })

    def handle_data(self, data):
        if self.skip:
            return
        if self.pre:
            for i, p in enumerate(data.split('\n')):
                if i:
                    self._nl()
                self.cur += p
        else:
            text = re.sub(r'[ \t\r\n]+', ' ', data)
            if not text or (text == ' ' and not self.cur):
                return
            if text.startswith(' ') and not self.cur:
                text = text.lstrip()
            self.cur += text

    def result(self):
        self._enl()
        # Return lines as an array so anchor indices stay consistent with line positions.
        return {'lines': self.out, 'links': self.links, 'anchors': self.anch}


if __name__ == '__main__':
    with open(sys.argv[1], encoding='utf-8', errors='replace') as f:
        html = f.read()
    p = RFCParser()
    p.feed(html)
    print(json.dumps(p.result()))
