# Repro: Omarchy free-space install fails to mount the ESP

Ephemeral KVM/libvirt VM. `down` removes the domain, UEFI NVRAM, and disk.

Omarchy 4.x **Free space install** fails to mount the EFI System Partition (ESP) when the target disk already has a data partition and **no** FAT32 ESP on that disk:

```
mount: /mnt/boot: fsconfig() failed: Can't find a SQUASHFS superblock on <part>
mounting the ESP failed (exit 32)
```

[Issue #7515](https://github.com/omacom/omarchy/issues/7515). The configurator runs `mount "$efi_dev"` without `-t vfat`; the kernel walks `/proc/filesystems` and on the live ISO squashfs answers first. Known workaround: a dummy FAT32 EFI partition. Proposed fix: [omarchy-iso#111](https://github.com/omacom/omarchy-iso/pull/111) (`mount -t vfat`).

Verified end-to-end on Ubuntu: **[RUN-UBUNTU.md](RUN-UBUNTU.md)**. Other distributions: same playbook; install equivalent tools yourself. The playbook runs as the invoking user; it does not install packages or start services.

## Host

Working KVM (`/dev/kvm` readable and writable by **this** user) plus:

| Command | Role |
|---------|------|
| `ansible-playbook` | runner (`ansible-core`) |
| `qemu-img` | sparse disk |
| `virt-install`, `virsh` | libvirt `qemu:///system` |
| `virt-viewer` | console |
| `parted`, `mkfs.ext4` | GPT + ext4 `backup` without root |
| OVMF/edk2 firmware | UEFI, Secure Boot off |

Package **names** differ (Debian/Ubuntu `qemu-system-x86` + `ovmf`; Fedora/RHEL `qemu-kvm` + `edk2-ovmf`; Arch `qemu-desktop` + `edk2-ovmf`). The playbook checks binaries and firmware paths, not package-manager names.

ISO (Omarchy 4.x): https://iso.omarchy.org/ — not downloaded by the playbook. Place it on a path the libvirt qemu user can traverse **and** read (not a `0700` home directory; a symlink into home does not help). Default: `/var/tmp/omarchy.iso`.

Disk images default to `/var/tmp/omarchy-repro/` (mode `0755`).

The domain XML includes `<seclabel type='none'/>` so AppArmor/SELinux do not need a policy exception for `/var/tmp`. DAC (file mode/ownership) still applies. Pass `-e vm_seclabel=dynamic` only if the disk and ISO already live in a path `virt-aa-helper` allows (typically `/var/lib/libvirt/images`).

## Run

```bash
ansible-playbook playbook.yml -e omarchy_iso=/var/tmp/omarchy.iso
virt-viewer --connect qemu:///system omarchy-repro
```

Or `./repro.sh check|up|down|status`.

In the installer (manual; an unattended `cidata` drive skips the configurator and **misses** the bug):

1. Press Enter at the boot menu  
2. Keyboard layout  
3. Any username and password  
4. Disk **vda** → **Free space install** (not a full wipe)  
5. Confirm  

The failure is immediate (seconds), still on *Creating Btrfs filesystem and subvolumes*. The installer is **not** copying the system.

If the guest clipboard cannot copy text:

```bash
virsh --connect qemu:///system screenshot omarchy-repro /var/tmp/omarchy-esp-fail.ppm
```

Tear down:

```bash
ansible-playbook playbook.yml --tags down
```

## When it fires

After the wizard, `run_partition_execute`:

1. `parted` — 2 GiB ESP + root in free space  
2. `mkfs.btrfs` + `@` `@home` `@log` `@pkg`  
3. `mkfs.fat` on the new ESP  
4. **`mount "$efi_dev" /mnt/boot`** — fails here (`exit 32`, SQUASHFS)  

`archinstall` / pacstrap never start. Rollback deletes the new partitions; the disk looks unchanged (data partition and unallocated space).

## vda geometry

**80 GiB** (usable minimum 70 GiB). Omarchy requires at least 32 GiB of free space plus 2 GiB for the ESP it tries to create. 64 GiB at 50/50 is exactly 32 GiB, with no margin.

| Range | Contents |
|-------|----------|
| 0–50% | Free space (~40 GiB) |
| 50–100% | ext4 `backup` |

A 32 GiB disk with 50% free (~16 GiB) never hits the bug: the configurator aborts on space first.

NAT network: `vm_network` (default `default`). URI: `libvirt_uri` (`qemu:///system`). The domain is always `virsh define` + `virsh start` (EFI NVRAM does not work with `virsh create`). Pass `-e vm_transient=false` if the guest must survive a reboot; `down` still undefines it.
