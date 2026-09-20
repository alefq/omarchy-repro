#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

usage() {
  cat <<'EOF'
Usage: ./repro.sh check|up|down|status [-- extra-ansible...]

Runs as the invoking user. That user needs working KVM and the tools
listed in the README. Ubuntu: RUN-UBUNTU.md.

  check   Verify KVM, tools, libvirt, and ISO (installs nothing)
  up      Verify and start the ephemeral VM
  down    Power off, undefine --nvram, delete the disk
  status  virsh list for omarchy-repro

Example:
  ./repro.sh up -e omarchy_iso=/var/tmp/omarchy.iso
  virt-viewer --connect qemu:///system omarchy-repro
  ./repro.sh down
EOF
}

cmd="${1:-}"
if [[ -z "$cmd" || "$cmd" == "-h" || "$cmd" == "--help" ]]; then
  usage
  exit 0
fi
shift

case "$cmd" in
  check)
    exec ansible-playbook playbook.yml --tags check "$@"
    ;;
  up)
    exec ansible-playbook playbook.yml "$@"
    ;;
  down)
    exec ansible-playbook playbook.yml --tags down "$@"
    ;;
  status)
    virsh --connect qemu:///system list --all | grep -E 'Id|omarchy-repro' || echo "omarchy-repro VM not found"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
