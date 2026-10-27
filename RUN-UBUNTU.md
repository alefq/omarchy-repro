# Ubuntu — verified run

This is the host where the playbook was run end to end, through to the installer failure (SQUASHFS / `mounting the ESP failed`). The playbook is distro-agnostic; **package and group names below are Ubuntu-specific**.

The playbook runs as the invoking user. It does not install packages, start services, or change group membership.

## Host needs

- `/dev/kvm` present; this user can read and write it
- Groups `kvm` and `libvirt` on this user (reload the login session after changing them)
- Commands on `PATH`: `ansible-playbook`, `qemu-img`, `virt-install`, `virsh`, `virt-viewer`, `parted`, `mkfs.ext4`, `python3`
- UEFI firmware from package `ovmf` (`/usr/share/OVMF/…`)
- `libvirtd` running; libvirt network `default` active (`qemu:///system`)
- Omarchy 4.x ISO at `/var/tmp/omarchy.iso`, world-readable, not under a `0700` home (a symlink into home is not enough)
- AppArmor is expected. The playbook writes `<seclabel type='none'/>` into the domain XML so `virt-aa-helper` does not have to read `/var/tmp` (its profile typically allows `/var/lib/libvirt/images`, not `/var/tmp`). DAC still applies.

On current Ubuntu, `qemu-kvm` is a **virtual package**. Use a concrete provider (`qemu-system-x86` or `qemu-system-x86-hwe`), not `qemu-kvm`.

## Suggested commands

```bash
apt update
apt install -y \
  ansible-core \
  qemu-system-x86 qemu-utils \
  libvirt-daemon-system libvirt-clients virtinst \
  ovmf virt-viewer \
  parted e2fsprogs
systemctl start libvirtd
virsh --connect qemu:///system net-start default
usermod -aG libvirt,kvm "$USER"
```

Then a **new** login shell. Confirm:

```bash
id -nG
test -r /dev/kvm -a -w /dev/kvm && echo kvm ok
```

ISO (original file is not modified; the playbook opens the cdrom read-only):

```bash
cp --reflink=auto /path/to/omarchy.iso /var/tmp/omarchy.iso
chmod 0644 /var/tmp/omarchy.iso
```

`--reflink=auto`: copy-on-write if the filesystem supports it; otherwise a full copy.

`/var/tmp` on Debian/Ubuntu is cleaned after 30 days unused (`tmpfiles.d`, `q /var/tmp … 30d`). Keep the original ISO elsewhere.

## From a clean host (step 0)

Run in order on a machine that only has working KVM. Skip nothing: leftover groups, ISO paths, or a live domain will hide a missing step.

0. New login shell (log out/in or a new SSH session). Do not reuse `newgrp` from an old terminal.
1. Satisfy **Host needs** (suggested commands above).
2. `id` lists `kvm` and `libvirt`; `test -r /dev/kvm -a -w /dev/kvm` returns 0. If not, stop.
3. ISO at `/var/tmp/omarchy.iso`. Do not pass a path under `$HOME`.
4. From the repo root, as the same user that can use KVM:

   ```bash
   ansible-playbook playbook.yml --tags down
   ansible-playbook playbook.yml --tags check -e omarchy_iso=/var/tmp/omarchy.iso
   ansible-playbook playbook.yml -e omarchy_iso=/var/tmp/omarchy.iso
   virt-viewer --connect qemu:///system omarchy-repro
   ```

   Task names and fail text must be English (`Check KVM device`, `Reminder`, …).
5. In the guest: Enter → keyboard → any user/password → disk **vda** → **Free space install**. Expect `SQUASHFS` / `mounting the ESP failed` within seconds.
6. Capture and destroy:

   ```bash
   virsh --connect qemu:///system screenshot omarchy-repro /var/tmp/omarchy-esp-fail.ppm
   ansible-playbook playbook.yml --tags down
   ```

A new ephemeral host is ready to publish only if this sequence works without extra undocumented commands.

## Run (after the host already matches Host needs)

```bash
ansible-playbook playbook.yml -e omarchy_iso=/var/tmp/omarchy.iso
virt-viewer --connect qemu:///system omarchy-repro
```

Wizard: vda → **Free space install**. The error is immediate; if SPICE will not copy TUI text:

```bash
virsh --connect qemu:///system screenshot omarchy-repro /var/tmp/omarchy-esp-fail.ppm
ansible-playbook playbook.yml --tags down
```

`down` deletes `/var/tmp/omarchy-repro/` (the qcow2). It does not delete the ISO.

If `virsh start` fails with `cannot load AppArmor profile` even with `vm_seclabel=none`, libvirt is still loading AppArmor on this host. Once, as root:

```
# in /etc/libvirt/qemu.conf
security_driver = "none"
systemctl restart libvirtd
```

The playbook does not change `qemu.conf`. Do not set `vm_seclabel=dynamic` unless disk and ISO are in a path the helper already allows.
