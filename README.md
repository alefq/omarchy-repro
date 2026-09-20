# Reproducir el fallo ESP de Omarchy (free space + partición de datos)

Ambiente **efímero**: una VM KVM/libvirt que se tira con `down`. No queda dominio, ni NVRAM UEFI, ni disco.

El instalador de Omarchy 4.x, en **Free space install**, falla al montar la partición EFI (ESP, *EFI System Partition*) si el disco destino ya tiene una partición de datos y **no** hay un ESP FAT32 en ese mismo disco:

```
mount: /mnt/boot: fsconfig() failed: Can't find a SQUASHFS superblock on <part>
mounting the ESP failed (exit 32)
```

Es el [issue #7515](https://github.com/omacom/omarchy/issues/7515). El configurator hace `mount "$efi_dev"` sin `-t vfat`; el kernel recorre `/proc/filesystems` y en el live ISO responde primero squashfs. Workaround conocido: una EFI FAT32 dummy. Fix propuesto: [omarchy-iso#111](https://github.com/omacom/omarchy-iso/pull/111) (`mount -t vfat`).

## Cuándo dispara (antes de copiar el sistema)

No es un fallo de copia desde el medio. En hardware real (USB 3.0, NVMe SPCC) aparece en **≤ 1 min** tras confirmar *Free space install*: no hay tiempo de volcar el ISO.

El wizard ya terminó teclado/usuario/disco. `run_partition_execute` solo hace:

1. `parted` — ESP 2 G + root en el hueco libre
2. `mkfs.btrfs` + subvolúmenes + mounts de `@` `@home` `@log` `@pkg`
3. `mkfs.fat` del ESP nuevo
4. **`mount "$efi_dev" /mnt/boot`** — acá muere (`exit 32`, SQUASHFS)

La UI suele quedar en *Creating Btrfs filesystem and subvolumes*: ese `step` cubre 2–4. `archinstall` / pacstrap **no arrancan**; el JSON de instalación protegida se escribe *después* de ese `mount`. Al fallar, `rollback_created_parts` deshace las particiones nuevas: el disco vuelve a verse como al inicio (datos + hueco libre).

USB 3.0 vs USB 2.0 no cambia el resultado: el live ya está en RAM y el squashfs del ISO es justo el tipo que el `mount` sin `-t` prueba primero.

La geometría copia el patrón del SPCC (US75): mitad libre, mitad `backup` al final. Sin ESP.

## Requisitos en el host

El playbook **no pide sudo en ningún momento**: corre entero como el usuario que lo invoca (sin `become`, sin `-K`). Tampoco instala paquetes ni arranca servicios — comprueba y, si falta algo, imprime el comando. `./repro.sh check` es solo eso.

Lo único que hace falta es que ese usuario ya tenga permiso para crear VMs KVM: estar en los grupos `libvirt` y `kvm` (acceso estándar de Debian/Ubuntu a `qemu:///system` vía el socket de libvirtd, sin polkit/root de por medio) y que `/dev/kvm` sea accesible.

En el host, una vez (esto sí necesita sudo, pero es setup, no parte del repro):

```bash
sudo apt update
sudo apt install -y \
  ansible-core \
  qemu-system-x86 qemu-utils \
  libvirt-daemon-system libvirt-clients virtinst \
  ovmf virt-viewer \
  parted e2fsprogs
sudo systemctl start libvirtd
sudo virsh --connect qemu:///system net-start default
sudo usermod -aG libvirt,kvm "$USER"
# cerrá sesión y volvé a entrar para que el grupo tome efecto
```

SVM/AMD-V en BIOS (`kvm-ok` tiene que ver `/dev/kvm`). ISO de Omarchy 4.x a mano (~6 G); el playbook no la baja:

https://iso.omarchy.org/omarchy-4.0.4.iso

Disco e ISO van **fuera de `$HOME`**: `qemu:///system` corre como `libvirt-qemu` y no atraviesa un home `0700`/`0750`. Default: `vm_dir=/var/tmp/omarchy-repro`, ISO en `/var/tmp/omarchy.iso`. Un symlink al home no alcanza. No hace falta `chmod` del home.

```bash
cp --reflink=auto "$HOME/isos/omarchy.iso" /var/tmp/omarchy.iso
chmod 0644 /var/tmp/omarchy.iso
```

`/var/tmp` en Debian/Ubuntu se limpia a los 30 días sin uso (`tmpfiles.d`, `q /var/tmp … 30d`). El original del ISO conviene dejarlo en otro lado y copiar a `/var/tmp` antes de cada tanda; el playbook no toca esa política.

El particionado es user-space sobre un raw sparse (`parted` + `mkfs.ext4 -E offset=` → qcow2). No usa libguestfs ni NBD: no lee `/boot/vmlinuz`, no pide sudo.

## Uso

```bash
cd omarchy-repro
./repro.sh check -e omarchy_iso=/var/tmp/omarchy.iso
./repro.sh up -e omarchy_iso=/var/tmp/omarchy.iso
virt-viewer --connect qemu:///system omarchy-repro
```

En el instalador: disco **vda**, **Free space install**. No elijas wipe. Secure Boot ya va desactivado en OVMF (*Open Virtual Machine Firmware*). El error sale en segundos, todavía en el paso de Btrfs/ESP; no esperes la copia del sistema.

Cuando termines:

```bash
./repro.sh down
```

Equivalente Ansible:

```bash
ansible-playbook playbook.yml -e omarchy_iso=/var/tmp/omarchy.iso
ansible-playbook playbook.yml --tags down
```

`up` destruye leftover de una corrida anterior y recrea el disco. `--transient` (por defecto) undefine la VM al apagarla; `down` borra igual el qcow2 y el NVRAM.

## Geometría de vda

Disco de **80 G** (mínimo usable: 70 G). Omarchy exige ≥32 G de free space, más 2 G para el ESP que el instalador quiere crear. Con 64 G al 50/50 el hueco queda justo en 32 G, sin colchón.

| Rango | Contenido |
|-------|-----------|
| 0–50% | Free space (~40 G) |
| 50–100% | ext4 `backup` |

Un disco de 32 G con 50% libre (~16 G) **no** dispara el bug: el configurator aborta antes por espacio.

Red NAT: `vm_network` (default `default`). URI: `libvirt_uri` (`qemu:///system`).

## Qué no usar

Una unidad `cidata` de instalación desatendida **salta el configurator**. El fallo está en `run_partition_execute` del wizard interactivo; el autoinstall no lo recorre.

Para inspeccionar la VM después de un reboot del guest, pasá `-e vm_transient=false`.
