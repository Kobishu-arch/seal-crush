#!/usr/bin/env python3
"""Make a web build immune to GitHub Pages' ten-minute cache.

Pages serves everything with `cache-control: max-age=600` and we cannot change
that, while Godot exports fixed filenames (`index.wasm`, `index.pck`) with no
content hash. A returning visitor therefore gets a stale build for up to ten
minutes, and a plain reload re-reads the cache rather than refetching.

Hashing the filenames alone does not help: `index.html` is cached too, so a
returning visitor reads old HTML pointing at the old names it already holds.
The build id has to be discovered at load time from a URL that can never be
cached. So:

  * `version.txt` holds the build id.
  * A script injected into <head> reads `version.txt?t=<now>` - unique every
    load, therefore never served from cache - and appends `?v=<id>` to the
    .wasm and .pck requests, which forces a refetch whenever the build changes.

The injected script is byte-identical in every build, so `index.html` being
cacheable is harmless: the logic inside it runs fresh on every load.

    python3 tools/cachebust.py build <version>
"""
import os, sys

SNIPPET = """\t<script>
\t/* injected by tools/cachebust.py - see that file for why */
\t(function () {
\t\tvar v = null;
\t\ttry {
\t\t\tvar x = new XMLHttpRequest();
\t\t\tx.open('GET', 'version.txt?t=' + Date.now(), false);
\t\t\tx.send(null);
\t\t\tif (x.status >= 200 && x.status < 300) { v = x.responseText.trim(); }
\t\t} catch (e) { /* offline or blocked: fall back to whatever is cached */ }
\t\tif (!v) { return; }
\t\tvar bust = function (u) {
\t\t\tif (typeof u !== 'string' || !/\\.(wasm|pck)(\\?|$)/.test(u)) { return u; }
\t\t\tif (u.indexOf('v=') !== -1) { return u; }
\t\t\treturn u + (u.indexOf('?') === -1 ? '?' : '&') + 'v=' + v;
\t\t};
\t\tvar orig = window.fetch;
\t\twindow.fetch = function (input, init) {
\t\t\tif (typeof input === 'string') { input = bust(input); }
\t\t\telse if (input && input.url) { input = new Request(bust(input.url), input); }
\t\t\treturn orig.call(this, input, init);
\t\t};
\t})();
\t</script>
"""


def main():
    if len(sys.argv) < 3:
        sys.exit('usage: cachebust.py <build-dir> <version>')
    build, version = sys.argv[1], sys.argv[2].strip()
    html_path = os.path.join(build, 'index.html')
    html = open(html_path, encoding='utf-8').read()
    if 'tools/cachebust.py' in html:
        sys.exit('index.html already processed')
    if '</head>' not in html:
        sys.exit('no </head> in index.html - export format changed?')
    html = html.replace('</head>', SNIPPET + '\t</head>', 1)
    open(html_path, 'w', encoding='utf-8').write(html)
    with open(os.path.join(build, 'version.txt'), 'w', encoding='utf-8') as f:
        f.write(version + '\n')
    print('cache-busting injected, version %s' % version)


if __name__ == '__main__':
    main()
