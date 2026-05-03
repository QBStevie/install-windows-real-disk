#!/usr/bin/env bash
set -euo pipefail

# Full Linux -> Windows installer using QEMU on the REAL disk.
# WARNING: This overwrites Linux.

WINDOWS_ISO_URL="https://software-static.download.prss.microsoft.com/pr/download/20348.169.230217-1640.fe_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
VIRTIO_ISO_URL="https://fedora-virt.repo.nfrance.com/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

WORKDIR="/root/win-real-install"
RAM_MB="4096"
CPU_CORES="2"
VNC_PORT="1"

echo "================================================="
echo " FULL Linux -> Windows installer"
echo " THIS WILL WIPE YOUR SERVER DISK"
echo "================================================="

if [[ $EUID -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

DISK="$(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print "/dev/"$1; exit}')"

if [[ -z "${DISK}" ]]; then
  echo "Could not detect disk."
  exit 1
fi

echo "Detected real disk: $DISK"
echo
echo "Type YES to continue and wipe/install Windows on $DISK:"
read -r CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
  echo "Cancelled."
  exit 1
fi

echo "[1/7] Installing packages..."

if command -v apt >/dev/null 2>&1; then
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y qemu-system-x86 qemu-utils wget curl screen
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache qemu-system-x86_64 qemu-img wget curl screen
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y qemu-kvm qemu-img wget curl screen
elif command -v yum >/dev/null 2>&1; then
  yum install -y qemu-kvm qemu-img wget curl screen
else
  echo "Unsupported distro."
  exit 1
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[2/7] Downloading Windows ISO..."
wget -O windows.iso "$WINDOWS_ISO_URL"

echo "[3/7] Downloading VirtIO drivers..."
wget -O virtio-win.iso "$VIRTIO_ISO_URL"

echo "[4/7] Disabling swap..."
swapoff -a || true

echo "[5/7] Starting Windows installer on real disk..."
echo
echo "VNC tunnel from PowerShell:"
echo "ssh -L 5901:127.0.0.1:5901 root@23.230.139.250"
echo
echo "Then connect VNC Viewer to:"
echo "127.0.0.1:5901"
echo
echo "When Windows asks for disk driver:"
echo "Load driver > VirtIO CD > viostor > 2k22 > amd64"
echo

screen -S wininstall -dm bash -c "
qemu-system-x86_64 \
  -enable-kvm \
  -m $RAM_MB \
  -smp $CPU_CORES \
  -cpu host \
  -drive file=$DISK,format=raw,if=virtio,cache=none,aio=native \
  -cdrom $WORKDIR/windows.iso \
  -drive file=$WORKDIR/virtio-win.iso,media=cdrom \
  -boot d \
  -netdev user,id=n0,hostfwd=tcp::3389-:3389 \
  -device virtio-net-pci,netdev=n0 \
  -vnc 127.0.0.1:$VNC_PORT \
  -monitor stdio
"

echo "[6/7] Installer started."
echo
echo "Attach console:"
echo "screen -r wininstall"
echo
echo "Detach:"
echo "CTRL+A then D"
echo
echo "[7/7] After Windows finishes installing:"
echo "1. Shut down Windows inside VNC."
echo "2. Back in SSH, run:"
echo "   reboot -f"
echo
echo "Then try RDP to:"
echo "23.230.139.250:3389"
