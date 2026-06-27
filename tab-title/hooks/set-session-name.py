#!/usr/bin/env python3
"""Read/write the session label in a Copilot CLI workspace.yaml.

The label is stored as the session's own `name` (with `user_named: true`), so it
persists across tab reloads / restarts and is picked up by Copilot's own session
list. We edit the file line-by-line (verbatim) to avoid reformatting the YAML
the Rust runtime round-trips.

Usage:
  set-session-name.py --get <workspace.yaml>          # print name iff user_named:true
  set-session-name.py --set <workspace.yaml> <label>  # set name + user_named:true (atomic)
"""
import os
import sys
import tempfile
from datetime import datetime, timezone


def _unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        return v[1:-1].replace('\\"', '"').replace('\\\\', '\\')
    return v


def get_name(path):
    name, user_named = None, False
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                if line.startswith("name:"):
                    name = _unquote(line[len("name:"):])
                elif line.startswith("user_named:"):
                    user_named = line.split(":", 1)[1].strip() == "true"
    except OSError:
        return ""
    return name if (user_named and name) else ""


def set_name(path, label):
    label = label.strip()
    if not label:
        return 1
    quoted = '"' + label.replace("\\", "\\\\").replace('"', '\\"') + '"'
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + \
        f"{datetime.now(timezone.utc).microsecond // 1000:03d}Z"

    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
    except OSError:
        return 1

    out, seen = [], {"name": False, "user_named": False, "updated_at": False}
    for line in lines:
        if line.startswith("name:"):
            out.append(f"name: {quoted}\n"); seen["name"] = True
        elif line.startswith("user_named:"):
            out.append("user_named: true\n"); seen["user_named"] = True
        elif line.startswith("updated_at:"):
            out.append(f"updated_at: {now}\n"); seen["updated_at"] = True
        else:
            out.append(line)
    if not seen["name"]:
        out.append(f"name: {quoted}\n")
    if not seen["user_named"]:
        out.append("user_named: true\n")
    if not seen["updated_at"]:
        out.append(f"updated_at: {now}\n")

    d = os.path.dirname(path) or "."
    try:
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".ws-", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("".join(out))
        os.replace(tmp, path)
    except OSError:
        return 1
    return 0


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--get":
        print(get_name(sys.argv[2]))
        return 0
    if len(sys.argv) >= 4 and sys.argv[1] == "--set":
        return set_name(sys.argv[2], sys.argv[3])
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
