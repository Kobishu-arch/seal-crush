#!/usr/bin/env python3
"""Fetch only Godot's web export templates from the official template pack.

The pack is ~1.28 GB because it holds every platform. GitHub release assets
send `accept-ranges: bytes`, so we can read the zip's central directory and
pull just the `web_*` members - about 84 MB instead of 1,222 MB.

    python3 tools/fetch_web_templates.py 4.7.2 ~/.local/share/godot/export_templates/4.7.2.stable

Pass --pack <file> to extract from an already-downloaded pack instead.
"""
import io, os, shutil, sys, urllib.error, urllib.request, zipfile

URL = ("https://github.com/godotengine/godot/releases/download/"
       "{v}-stable/Godot_v{v}-stable_export_templates.tpz")

# urllib's default User-Agent ("Python-urllib/3.x") is commonly refused from
# datacenter IPs, which is why this worked from a workstation and 403'd on a
# CI runner while plain curl to the same host succeeded.
UA = {'User-Agent': 'seal-crush-ci (+https://github.com/Kobishu-arch/seal-crush)'}


def _open(url, extra=None, method=None):
    headers = dict(UA)
    if extra:
        headers.update(extra)
    return urllib.request.urlopen(
        urllib.request.Request(url, headers=headers, method=method))


class RangeFile(io.RawIOBase):
    """A seekable file-like view over an HTTP resource via range requests."""

    def __init__(self, url):
        with _open(url, method='HEAD') as r:
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
        with _open(self.url, {'Range': 'bytes=%d-%d' % (self.pos, end)}) as r:
            data = r.read()
        self.pos += len(data)
        self.fetched += len(data)
        return data


def _extract(zf, dest):
    members = [n for n in zf.namelist()
               if n.endswith('.zip') and 'web' in n.rsplit('/', 1)[-1].lower()]
    if not members:
        raise RuntimeError('no web templates found in the pack')
    for n in members:
        base = n.rsplit('/', 1)[-1]
        with zf.open(n) as src, open(os.path.join(dest, base), 'wb') as dst:
            dst.write(src.read())
        print('extracted', base)
    return members


def ranged(url, dest):
    rf = RangeFile(url)
    _extract(zipfile.ZipFile(rf), dest)
    print('downloaded %.1f MB of %.1f MB via range requests'
          % (rf.fetched / 1048576.0, rf.size / 1048576.0))


def whole_pack(url, dest):
    """Fallback: pull the entire pack, then extract. Slow but dependable."""
    tmp = os.path.join(dest, '_pack.tpz')
    try:
        with _open(url) as r, open(tmp, 'wb') as f:
            shutil.copyfileobj(r, f, 1 << 20)
        print('downloaded full pack: %.1f MB' % (os.path.getsize(tmp) / 1048576.0))
        with zipfile.ZipFile(tmp) as zf:
            _extract(zf, dest)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def main():
    if len(sys.argv) < 3:
        sys.exit('usage: fetch_web_templates.py <version> <dest-dir> [--pack FILE]')
    version, dest = sys.argv[1], sys.argv[2]
    os.makedirs(dest, exist_ok=True)
    if '--pack' in sys.argv:
        pack = sys.argv[sys.argv.index('--pack') + 1]
        with zipfile.ZipFile(pack) as zf:
            _extract(zf, dest)
        return
    url = URL.format(v=version)
    try:
        ranged(url, dest)
    except Exception as exc:                       # noqa: BLE001 - report and retry
        detail = exc
        if isinstance(exc, urllib.error.HTTPError):
            detail = '%s %s' % (exc.code, exc.reason)
        print('range fetch failed (%s); falling back to the full pack' % detail,
              file=sys.stderr)
        whole_pack(url, dest)


if __name__ == '__main__':
    main()
