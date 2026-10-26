#!/usr/bin/env python3
"""Fetch only Godot's web export templates from the official template pack.

The pack is ~1.28 GB because it holds every platform. GitHub release assets
send `accept-ranges: bytes`, so we can read the zip's central directory and
pull just the `web_*` members - about 84 MB instead of 1,222 MB.

    python3 tools/fetch_web_templates.py 4.7.2 ~/.local/share/godot/export_templates/4.7.2.stable
"""
import io, os, sys, urllib.request, zipfile

URL = ("https://github.com/godotengine/godot/releases/download/"
       "{v}-stable/Godot_v{v}-stable_export_templates.tpz")


class RangeFile(io.RawIOBase):
    """A seekable file-like view over an HTTP resource via range requests."""

    def __init__(self, url):
        req = urllib.request.Request(url, method='HEAD')
        with urllib.request.urlopen(req) as r:
            self.size = int(r.headers['Content-Length'])
            self.url = r.geturl()
        self.pos = 0
        self.fetched = 0

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (
            self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def tell(self):
        return self.pos

    def seekable(self):
        return True

    def readable(self):
        return True

    def read(self, n=-1):
        if n < 0:
            n = self.size - self.pos
        if n == 0:
            return b''
        end = min(self.pos + n, self.size) - 1
        req = urllib.request.Request(
            self.url, headers={'Range': 'bytes=%d-%d' % (self.pos, end)})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        self.pos += len(data)
        self.fetched += len(data)
        return data


def main():
    if len(sys.argv) < 3:
        sys.exit('usage: fetch_web_templates.py <version> <dest-dir>')
    version, dest = sys.argv[1], sys.argv[2]
    os.makedirs(dest, exist_ok=True)
    rf = RangeFile(URL.format(v=version))
    zf = zipfile.ZipFile(rf)
    members = [n for n in zf.namelist()
               if n.endswith('.zip') and 'web' in n.rsplit('/', 1)[-1].lower()]
    if not members:
        sys.exit('no web templates found in the pack')
    for n in members:
        base = n.rsplit('/', 1)[-1]
        with zf.open(n) as src, open(os.path.join(dest, base), 'wb') as dst:
            dst.write(src.read())
        print('extracted', base)
    print('downloaded %.1f MB of %.1f MB'
          % (rf.fetched / 1048576.0, rf.size / 1048576.0))


if __name__ == '__main__':
    main()
