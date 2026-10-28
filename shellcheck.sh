#!/bin/bash
#
# Run shellcheck on the driver shell scripts.
# Options and source lookup are in .shellcheckrc.
#
# Usage: ./shellcheck.sh [file ...]
# With no arguments, the driver globs below are used.
# Extra arguments replace that list. The shell expands globs before
# this script sees them.

set -euo pipefail

cd "$(dirname -- "$(realpath -- "$0")")"
shopt -s nullglob

if [[ $# -gt 0 ]]; then
    _candidates=("$@")
else
    _candidates=(
        install.sh
        misc/reserved.sh
        misc/storpool_probe.sh
        misc/tagVolumes.sh
        misc/kvresolve.sh
        misc/vmdisk_restore.sh
        tm/storpool/*
        datastore/storpool/*
        vmm/kvm/deploy-tweaks
        vmm/kvm/attach_disk*
        vmm/kvm/detach_disk*
        vmm/kvm/save*
        vmm/kvm/restore*
        vmm/kvm/tmsaverestore
        vmm/kvm/snapshot*
        hooks/volumecare/*
    )
fi

declare -A _seen=()
declare -a FILES=()
for _file in "${_candidates[@]}"; do
    [[ -f "${_file}" ]] || continue
    [[ "${_file}" == *.py ]] && continue
    _shebang="$(head -n 1 -- "${_file}" || true)"
    [[ "${_shebang}" == *python* ]] && continue
    _real="$(realpath -- "${_file}")"
    [[ -v "_seen[${_real}]" ]] && continue
    _seen["${_real}"]=1
    FILES+=("${_file}")
done

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "shellcheck.sh: no shell files to check" >&2
    exit 1
fi

shellcheck "${FILES[@]}"
