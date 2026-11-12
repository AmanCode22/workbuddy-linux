#!/usr/bin/env python3
"""Patch the WorkBuddy app.asar credential-bootstrap env key at build time.

The official darwin app.asar sets WORKBUDDY_AT_REST_ENCRYPTION for every child
process (daemon, sidecar, CLI prewarm pool) and delivers a managed credential
bootstrap that requires the fork-only electron.workbuddyStorage API — which
vanilla Electron (what this port pairs the asar with) does not have. The
bundled CodeBuddy CLI then classifies startup as "managed-invalid" and every
session fails with CREDENTIAL_BOOTSTRAP_FAILED.

Fix (see ../README.md troubleshooting): rename the env key to a same-length
dummy name (WORKBUDDY_AT_REST_ENCRYPTIOX) at the 5 places where the host
sets/reads it. Replacements are byte-length-identical and in-place, so asar
offsets, the directory header and the file size stay valid — no repack.
Without the env var the CLI starts in supported "standalone" mode.

Build usage (called by assemble-app.sh right after app.asar is staged):

    python3 scripts/patch-credential-bootstrap.py <path/to/app.asar>
        patch    the staged asar (idempotent; skips already-patched sites)
        --check  report patch state only, no changes
        --skip-patch / --lenient   warn instead of failing when a context is
                                   not found (e.g. a newer upstream minified
                                   the code differently)

Exit codes: 0 = all sites patched (or already patched), 1 = at least one
context not found / asar version mismatch, 2 = usage error.
"""
import json
import struct
import sys

KEY = b"WORKBUDDY_AT_REST_ENCRYPTION"        # 28 bytes
DUMMY = b"WORKBUDDY_AT_REST_ENCRYPTIOX"      # 28 bytes, unused name
assert len(KEY) == len(DUMMY)

# (file inside asar, unique context containing the env key to rename)
SITES = [
    ("main/cli-prewarm-pool.js",
     b"f.WORKBUDDY_AT_REST_ENCRYPTION=this.deps.credentialProtectionBootstrap.policy"),
    ("main/credential-protection-bootstrap.js",
     b"var t=`WORKBUDDY_AT_REST_ENCRYPTION`,n="),
    ("main/main-bootstrap.js",
     b"WORKBUDDY_AT_REST_ENCRYPTION:o,WORKBUDDY_APP_NAME:"),
    ("main/sidecar-entry.js",
     b"WORKBUDDY_AT_REST_ENCRYPTION:this.credentialProtectionState.getPolicy()"),
    ("main/sidecar-manager.js",
     b"WORKBUDDY_AT_REST_ENCRYPTION:this.credentialProtectionBootstrap.policy"),
]


def iter_files(path):
    """Yield (relative path, absolute data offset, size) for each stored file."""
    with open(path, "rb") as f:
        head = f.read(16)
        _, b = struct.unpack("<II", head[:8])
        json_len = struct.unpack("<I", head[8:12])[0]
        raw = f.read(json_len)
        data_start = 8 + b
    header, _ = json.JSONDecoder().raw_decode(raw.decode("utf-8", "replace"))

    def walk(node, prefix=""):
        for name, ch in node.get("files", {}).items():
            p = f"{prefix}/{name}" if prefix else name
            if "files" in ch:
                yield from walk(ch, p)
            elif "size" in ch and not ch.get("unpacked"):
                yield p, data_start + int(ch["offset"]), ch["size"]

    yield from walk(header)


def site_blobs(asar):
    """Yield (prefix, file offset, size) for each patch site present."""
    want = {p for p, _ in SITES}
    for path, start, size in iter_files(asar):
        if path in want:
            yield path, start, size


def patch(asar, strict=True, check_only=False):
    ok = True
    total = 0
    by_prefix = {}
    for path, start, size in site_blobs(asar):
        by_prefix.setdefault(path, []).append((start, size))

    with open(asar, "r+b" if not check_only else "rb") as f:
        for prefix, ctx in SITES:
            new = ctx.replace(KEY, DUMMY)
            assert len(new) == len(ctx)
            blobs = by_prefix.get(prefix, [])
            if not blobs:
                print(f"patch-credential-bootstrap: {prefix}: CONTEXT NOT FOUND "
                      "(upstream code changed?)")
                if strict or check_only:
                    ok = False
                else:
                    print(f"{prefix}: continuing (--lenient/--skip-patch)")
                continue
            for start, size in blobs:
                f.seek(start)
                blob = f.read(size)
                n = blob.count(ctx)
                if n:
                    if check_only:
                        print(f"{prefix}: ORIGINAL (unpatched)")
                        ok = False
                    else:
                        f.seek(start)
                        f.write(blob.replace(ctx, new))
                        total += n
                        print(f"{prefix}: patched ({n} occurrence)")
                elif blob.count(new):
                    print(f"{prefix}: already patched")
                else:
                    print(f"{prefix}: CONTEXT NOT FOUND (upstream code changed?)")
                    if strict or check_only:
                        ok = False
                    else:
                        print(f"{prefix}: continuing (--lenient/--skip-patch)")

    if not check_only:
        import os
        print(f"patch-credential-bootstrap: {total} replacement(s) applied "
              f"to {asar} (size unchanged: {os.path.getsize(asar)} bytes)")
    return ok


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    flags = {a for a in argv if a.startswith("--")}
    unknown = flags - {"--check", "--lenient", "--skip-patch"}
    if len(args) != 1 or unknown:
        print(__doc__)
        return 2
    strict = not ({"--lenient", "--skip-patch"} & flags)
    if not patch(args[0], strict=strict, check_only="--check" in flags):
        if "--check" in flags:
            print("patch-credential-bootstrap: asar is NOT fully patched")
        else:
            print("patch-credential-bootstrap: FAILED — update SITES in "
                  "scripts/patch-credential-bootstrap.py for the new upstream "
                  "build, or pass --lenient to ship unpatched")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
