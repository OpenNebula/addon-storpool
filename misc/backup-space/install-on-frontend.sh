#!/bin/bash
#
# Install the StorPool sidebar on this front-end.
# misc/backup-space/ is /var/lib/one/remotes/misc/backup-space/.
# misc/etc/ is /etc/: the systemd unit, the nginx snippet, and the FireEdge
# tab and view files, each already in the directory it has on the front-end.
# The remote is registered only after /storpool/remoteEntry.js answers,
# because a remote that fails to load stops Sunstone.
#
set -euo pipefail

ROOT="$(dirname "$(readlink -f "$0")")"
ETC="$(dirname "${ROOT}")/etc"
ONE_VAR="${ONE_VAR:-/var/lib/one}"
DEST="${ONE_VAR}/remotes/misc/backup-space"
NGINX_CONF="${NGINX_CONF:-/etc/nginx/conf.d/frontend.conf}"
SUNSTONE="${SUNSTONE:-/etc/one/fireedge/sunstone}"
INCLUDE="include snippets/storpool-backup.conf;"

install -d -o oneadmin -g oneadmin "$(dirname "$DEST")"
rsync -a --chown=oneadmin:oneadmin \
    --exclude='install-on-frontend.sh' --exclude='__pycache__/' \
    "${ROOT}/" "${DEST}/"

install -o root -g root -m 0644 "${ETC}/systemd/system/backup-space.service" /etc/systemd/system/backup-space.service
systemctl daemon-reload
systemctl enable --now backup-space.service

install -d -o root -g root -m 0755 /etc/nginx/snippets
install -o root -g root -m 0644 "${ETC}/nginx/snippets/storpool-backup.conf" /etc/nginx/snippets/storpool-backup.conf

python3 - "$NGINX_CONF" "$INCLUDE" <<'PY'
import sys
path, include = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
if include in text:
    sys.exit(0)
lines = text.splitlines(keepends=True)
out = []
i = 0
while i < len(lines):
    out.append(lines[i])
    if lines[i].strip() == "root         /usr/share/nginx/html;":
        window = "".join(lines[i:i + 12])
        if "proxy_pass http://fireedge;" in window:
            indent = lines[i][:len(lines[i]) - len(lines[i].lstrip())]
            out.append("%s%s\n" % (indent, include))
    i += 1
open(path, "w", encoding="utf-8").write("".join(out))
PY

nginx -t
systemctl reload nginx

# Port 80's default server is not this vhost. The name is the one that
# block lists, not a host from the lab that produced the script.
HOST_HDR="$(python3 - "${NGINX_CONF}" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
for i, line in enumerate(lines):
    if line.strip() != "root         /usr/share/nginx/html;":
        continue
    start = 0
    for j, prev in enumerate(lines[:i]):
        if prev.strip() == "server {":
            start = j
    end = len(lines)
    for j in range(i + 1, len(lines)):
        if lines[j].strip() == "server {":
            end = j
            break
    block = lines[start:end]
    if not any(l.strip().startswith("proxy_pass") and "http://fireedge" in l for l in block):
        continue
    for prev in block:
        parts = prev.split()
        if parts and parts[0] == "server_name":
            name = parts[1].rstrip(";")
            if name and name != "_":
                print(name)
                raise SystemExit(0)
    raise SystemExit(1)
raise SystemExit(1)
PY
)"
curl -fsS -H "Host: ${HOST_HDR}" "http://127.0.0.1/storpool/remoteEntry.js" | grep -q "window.StorpoolModule"

install -o root -g root -m 0644 "${ETC}/one/fireedge/sunstone/tabs/storpool-tab.yaml" "${SUNSTONE}/tabs/storpool-tab.yaml"
for view in admin groupadmin user cloud; do
    install -o root -g root -m 0644 "${ETC}/one/fireedge/sunstone/views/${view}/storpool-tab.yaml" "${SUNSTONE}/views/${view}/storpool-tab.yaml"
done

if ! grep -q '^StorpoolModule:' "${SUNSTONE}/remotes-config.yaml"; then
    cat >> "${SUNSTONE}/remotes-config.yaml" <<'EOF'

StorpoolModule:
  name: StorpoolModule
  entry: __HOST__/storpool/remoteEntry.js
EOF
fi

echo "StorPool sidebar installed. Reload Sunstone in the browser."
