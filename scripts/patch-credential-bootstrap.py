#!/usr/bin/env python3
"""Patch the WorkBuddy app.asar credential-bootstrap env key at build time.

The official darwin app.asar sets WORKBUDDY_AT_REST_ENCRYPTION for every child
process (daemon, sidecar, CLI prewarm pool) and delivers a managed credential
bootstrap that requires the fork-only electron.workbuddyStorage API — which
vanilla Electron (what this port pairs the asar with) does not have. The
bundled CodeBuddy CLI then classifies startup as "managed-invalid" and every
session fails with CREDENTIAL_BOOTSTRAP_FAILED.

Fix (see ../README.md troubleshooting): rename the env key to a same-length
dummy name (WORKBUDDY_AT_REST_ENCRYPTIOX) wherever the host sets/reads it.
Replacements are byte-length-identical and in-place, so asar offsets, the
directory header and the file size stay valid — no repack. Without the env
var the CLI starts in supported "standalone" mode.

Version-robust matching (v2):
  Upstream ships as minified JS whose local variable names (f, m, ...) change
  between releases — WorkBuddy 5.11.4 renamed the cli-prewarm-pool.js binding
  and wrapped it in a guard, which broke the exact byte-context matching used
  before. Instead of pinning full statements, this version:

    1. walks the asar directory and finds EVERY occurrence of the env key,
    2. patches all occurrences inside the known host files listed in SITES,
    3. treats the key appearing in any OTHER file as a structural change:
       strict mode fails the build, --lenient patches it with a warning,
    4. treats a SITES file that no longer contains the key (renamed/removed
       upstream) the same way, so restructures still fail loudly.

  Renaming is safe regardless of the surrounding minified syntax because only
  the 28-byte key itself is replaced (guard chars, commas, backticks untouched).
  Verified against upstream builds 5.9.4.42593613 and 5.11.4.44121853.

Build usage (called by assemble-app.sh right after app.asar is staged):

    python3 scripts/patch-credential-bootstrap.py <path/to/app.asar>
        patch    the staged asar (idempotent; skips already-patched sites)
        --check  report patch state only, no changes
        --skip-patch / --lenient   warn instead of failing when the key shows
                                   up in an unexpected file or a known host
                                   file no longer contains it (e.g. a newer
                                   upstream restructured the bootstrap)

Exit codes: 0 = all sites patched (or already patched), 1 = at least one
context not found / unexpected site / asar version mismatch, 2 = usage error.
"""
import json
import os
import struct
import sys

KEY = b"WORKBUDDY_AT_REST_ENCRYPTION"        # 28 bytes
DUMMY = b"WORKBUDDY_AT_REST_ENCRYPTIOX"      # 28 bytes, unused name
assert len(KEY) == len(DUMMY)

# Host files that set/read the managed credential env key (asar-relative).
# Every occurrence of KEY inside these files is renamed KEY -> DUMMY.
# If upstream adds a new host file, the unexpected-site guardrail below will
# fail the strict build; add it here once identified.
SITES = [
    "main/cli-prewarm-pool.js",
    "main/credential-protection-bootstrap.js",
    "main/main-bootstrap.js",
    "main/sidecar-entry.js",
    "main/sidecar-manager.js",
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


def patch(asar, strict=True, check_only=False):
    """Rename KEY -> DUMMY in every SITES file (and unexpected hosts in lenient).

    Returns True when the asar ends up fully patched with no surprises.
    """
    known = set(SITES)
    # (offset, size) per file, plus a flag for whether the file is a known site
    blobs = {}
    for path, start, size in iter_files(asar):
        blobs[path] = (start, size, path in known)

    unexpected = []   # files holding KEY outside SITES
    missing = []      # SITES files with neither KEY nor DUMMY
    absent = []       # SITES files no longer stored in the asar at all
    total = 0
    ok = True

    mode = "rb" if check_only else "r+b"
    with open(asar, mode) as f:
        for path, (start, size, is_site) in blobs.items():
            f.seek(start)
            blob = f.read(size)
            n_key = blob.count(KEY)
            n_dummy = blob.count(DUMMY)
            if n_key:
                if not is_site:
                    unexpected.append(path)
                    print(f"{path}: UNEXPECTED SITE — "
                          + (f"found {n_key} occurrence"
                             f"{'s' if n_key != 1 else ''}; add it to SITES"
                             if check_only else
                             "patching anyway; add it to SITES"))
                    if strict:
                        ok = False
                if check_only:
                    print(f"{path}: ORIGINAL (unpatched, {n_key} occurrence"
                          f"{'s' if n_key != 1 else ''})")
                    ok = False
                else:
                    new = blob.replace(KEY, DUMMY)
                    assert len(new) == len(blob)
                    f.seek(start)
                    f.write(new)
                    total += n_key
                    print(f"{path}: patched ({n_key} occurrence"
                          f"{'s' if n_key != 1 else ''})")
            elif n_dummy:
                if is_site:
                    print(f"{path}: already patched")
                # a fully renamed unexpected file needs no action or warning
            elif is_site:
                missing.append(path)
                print(f"{path}: KEY NOT FOUND (upstream code changed?)")
                if strict or check_only:
                    ok = False
                else:
                    print(f"{path}: continuing (--lenient/--skip-patch)")

    for path in known:
        if path not in blobs:
            absent.append(path)
            print(f"{path}: FILE NOT IN ASAR (upstream code changed?)")
            if strict or check_only:
                ok = False

    if unexpected and strict and not check_only:
        print("patch-credential-bootstrap: env key found outside SITES — "
              "update SITES in scripts/patch-credential-bootstrap.py for the "
              "new upstream build (or pass --lenient)")

    if not check_only:
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
    if not os.path.isfile(args[0]):
        print(f"patch-credential-bootstrap: no such file: {args[0]}")
        return 2
    if not patch(args[0], strict=strict, check_only="--check" in flags):
        if "--check" in flags:
            print("patch-credential-bootstrap: asar is NOT fully patched")
        else:
            print("patch-credential-bootstrap: FAILED — update SITES in "
                  "scripts/patch-credential-bootstrap.py for the new upstream "
                  "build, or pass --lenient to ship unpatched")
        return 1
    if "--check" in flags:
        print("patch-credential-bootstrap: asar is fully patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
