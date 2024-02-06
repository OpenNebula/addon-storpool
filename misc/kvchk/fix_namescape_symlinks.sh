#!/bin/bash
#

set -e -o pipefail

me="${0##*/}"

NOOP="${NOOP:-}"

VMNAME="$1"

function do_symlink()
{
    local pid="$1" disk="$2"
    local target="" spdev=""
    [[ -n "${disk}" ]] || return 0
    target="$(readlink "${disk}" || true)"
    if [[ "${target}" =~ "storpool" ]]; then
        spdev="$(realpath "${target}")"
        if [[ -n "$spdev" ]]; then
            ${NOOP:+echo} nsenter -m -t "${pid}" ln -vsf "${spdev}" "${target}"
            logger -t "${me}" "PID ${pid} DISK ${disk} ln ${target} -> ${spdev} ($?)"
        else
            echo "[!] disk ${disk} target ${target} can't get realpath!"
        fi
    else
        echo "[!] Disk ${disk} with target ${target} not on storpool!"
    fi
}

if [[ -z "${VMNAME}" ]]; then
    echo "Usage: $0 vmname"
    exit 1
fi

PID="$(pgrep -f "guest=${VMNAME}," )"

if [[ -z "$PID" ]]; then
    echo "Guest with name ${VMNAME} not found!"
    exit 1
fi

${NOOP:+echo} nsenter -m -t "${PID}" mkdir -vp /dev/storpool-byid

DOMXML=$(mktemp "/var/run/${me}-XXXXXXX")
trap "rm -f ${DOMXML}" EXIT QUIT TERM

virsh dumpxml "${VMNAME}" >"${DOMXML}"

while read -ru 4 diskpath; do
    do_symlink "${PID}" "$diskpath" 
done 4< <(xmlstarlet sel -t -m '//devices/disk/source' -v '@dev' -n "${DOMXML}" 2>/dev/null || true)

while read -ru 4 diskpath; do
    do_symlink "${PID}" "$diskpath" 
done 4< <(xmlstarlet sel -t -m '//devices/disk/source' -v '@file' -n "${DOMXML}" 2>/dev/null || true)

