#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

usage() {
  cat <<'EOF'
Uso: ./repro.sh check|up|down|status [-- extra-ansible...]

No pide sudo: corre entero como el usuario que lo invoca. Requisito único
en el host: ese usuario en los grupos libvirt y kvm (ver README).

  check   Verifica KVM, paquetes, libvirt e ISO (no instala nada)
  up      Verifica y levanta la VM efímera
  down    Apaga, undefine --nvram y borra el disco
  status  virsh list de omarchy-repro

Ejemplo:
  ./repro.sh up -e omarchy_iso=/ruta/omarchy-4.0.4.iso
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
    virsh --connect qemu:///system list --all | grep -E 'Id|omarchy-repro' || echo "no hay VM omarchy-repro"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
