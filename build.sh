#!/bin/bash
set -e

# Global Configuration
GITHUB="https://github.com"
WORK_DIR=$(pwd)
IMAGE="ewe-vf2.img"
TARGET="${WORK_DIR}/target"
LOOP_DEV=""
CROSS_COMPILE="riscv64-linux-gnu-"  # RISC-V toolchain prefix
WGET="wget --progress=bar -c"


# Build OpenSBI
echo "Building OpenSBI..."
git clone ${GITHUB}/riscv/opensbi.git
cd opensbi
make CROSS_COMPILE=${CROSS_COMPILE} PLATFORM=generic FW_TEXT_START=0x40000000 FW_OPTIONS=0 -j$(nproc)
cd ${WORK_DIR}

# Build U-Boot
echo "Building U-Boot..."
git clone ${GITHUB}/u-boot/u-boot.git
cd u-boot
make starfive_visionfive2_defconfig
make CROSS_COMPILE=${CROSS_COMPILE} OPENSBI=../opensbi/build/platform/generic/firmware/fw_dynamic.bin -j$(nproc)
cd ${WORK_DIR}

# Prepare Disk Image
echo "Creating disk image..."
rm -f ${IMAGE}
fallocate -l 2250M ${IMAGE}
LOOP_DEV=$(sudo losetup -f -P --show "${IMAGE}")
cd ${WORK_DIR}

# Partition layout:
# 1: SPL (2M)
# 2: U-Boot (4M)
# 3: EFI (512M FAT32)
# 4: RootFS (remaining space ext4)
echo "[4/7] Partitioning..."
sudo sfdisk ${LOOP_DEV} << EOF
label: gpt
start=4MiB, size=4MiB, type=2E54B353-1271-4842-806F-E436D6AF6985
size=8MiB, type=BC13C2FF-59E6-4262-A352-B275FD6F7172
size=512MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF
sudo partprobe ${LOOP_DEV}

# Write Bootloaders
echo "Writing boot components..."
sudo dd if=u-boot/spl/u-boot-spl.bin.normal.out of=${LOOP_DEV}p1 bs=128k conv=fsync
sudo dd if=u-boot/u-boot.itb of=${LOOP_DEV}p2 bs=128k conv=fsync

# Prepare Filesystems
echo "Formatting partitions..."
sudo mkfs.vfat -F32 -n EFI ${LOOP_DEV}p3
sudo mkfs.ext4 -L VF2 ${LOOP_DEV}p4

# Setup RootFS 
echo "Deploying eweOS..."
sudo mkdir -p ${TARGET}
sudo mount ${LOOP_DEV}p4 ${TARGET}
sudo mkdir -p ${TARGET}/boot
sudo mount ${LOOP_DEV}p3 ${TARGET}/boot

sudo cp u-boot/spl/u-boot-spl.bin.normal.out ${TARGET}/boot
sudo cp u-boot/u-boot.itb ${TARGET}/boot

# Extract base system
${WGET} https://os-repo-lu.ewe.moe/eweos-images/eweos-riscv64-tarball.tar.xz
sudo tar -xf eweos-riscv64-tarball.tar.xz -C ${TARGET} --numeric-owner

# Chroot setup
sudo mount -t proc proc ${TARGET}/proc
sudo mount -t sysfs sysfs ${TARGET}/sys
sudo mount -t devtmpfs devtmpfs ${TARGET}/dev

# Execute in chroot
sudo chroot ${TARGET} /bin/bash << EOF
cat > /etc/resolv.conf << RESOLV_EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
RESOLV_EOF
pacman -Syu --noconfirm linux
cat > /etc/fstab << FSTAB_EOF
# /etc/fstab: static file system information
# <file system>                           <mount point>  <type>  <options>                                       <dump> <pass>
/dev/disk/by-label/VF2                    /              ext4    defaults,noatime                                0       1
/dev/disk/by-label/EFI                    /boot          vfat    defaults,noatime                                0       2
FSTAB_EOF

# Configure initramfs
cat > /etc/tinyramfs/config << CFG_EOF
hooks=mdev
compress=cat
root=/dev/disk/by-label/VF2
CFG_EOF

# Setup bootloader
limine-install --removable /boot
limine-mkconfig -o /boot/limine.conf
ln -s /usr/lib/dinit.d/getty /etc/dinit.d/boot.d/getty@ttyS0
EOF

# Cleanup
cleanup() {
  echo "Cleaning up..."
  sudo umount -f ${TARGET}/proc 2>/dev/null || true    
  sudo umount -f ${TARGET}/sys 2>/dev/null || true     
  sudo umount -f ${TARGET}/dev 2>/dev/null || true     
  sudo umount -f ${TARGET} 2>/dev/null || true         
  
  if [ -n "${LOOP_DEV}" ]; then
    sudo losetup -d ${LOOP_DEV} 2>/dev/null || true
  fi
  echo "Cleanup completed"
}

sudo umount -R ${TARGET} 2>/dev/null || true
if [ -n "${LOOP_DEV}" ]; then
  sudo losetup -d ${LOOP_DEV} 2>/dev/null || true
fi
echo "Image build completed: ${IMAGE}"

trap cleanup EXIT
