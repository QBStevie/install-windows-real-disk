#!/usr/bin/env bash
set -euo pipefail

# FULL Linux -> Windows installer (REAL DISK)
# ⚠️ THIS WILL WIPE YOUR SERVER

# ISO fallback list (tries each until one works)
ISO_LIST=(
"https://mirror.koddos.net/microsoft/windows-server-2022.iso"
"http://microsoft.windowsmirrors.net/Server%202025/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
)

VIRTIO_ISO_URL="https://fedora-virt.repo.nfrance.com/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

WORKDIR="/root/win-install"
RAM_MB="4096"
CPU_CORES="2"
VNC_PORT="1"

echo "================================================="
echo " ⚠️ FULL WINDOWS INSTALL (WILL WIPE LINUX)"
echo "================================================="

if [[ $EUID -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

DISK="$(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print "/dev/"$1; exit}')"

echo "Detected disk: $DISK"
echo "Type YES to continue:"
read -r CONFIRM

[[ "$CONFIRM" != "YES" ]] && echo "Cancelled." && exit 1

echo "[1] Installing packages..."

apt update -y || true
apt install -y qemu-system-x86 qemu-utils wget curl screen || true

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[2] Downloading Windows ISO (with fallback)..."

SUCCESS=0
for ISO in "${ISO_LIST[@]}"; do
  echo "Trying: $ISO"
  if wget -O windows.iso "$ISO"; then
    SUCCESS=1
    break
  else
    echo "Failed, trying next..."
    rm -f windows.iso
  fi
done

if [[ $SUCCESS -ne 1 ]]; then
  echo "❌ All ISO downloads failed."
  exit 1
fi

echo "[3] Downloading VirtIO..."
wget -O virtio-win.iso "$VIRTIO_ISO_URL"

echo "[4] Disable swap..."
swapoff -a || true

echo "[5] Starting installer..."

echo "Open VNC via SSH tunnel:"
echo "ssh -L 5901:127.0.0.1:5901 root@YOUR_IP"

screen -S wininstall -dm bash -c "
qemu-system-x86_64 \
  -enable-kvm \
  -m $RAM_MB \
  -smp $CPU_CORES \
  -cpu host \
  -drive file=$DISK,format=raw,if=virtio \
  -cdrom $WORKDIR/windows.iso \
  -drive file=$WORKDIR/virtio-win.iso,media=cdrom \
  -boot d \
  -netdev user,id=n0,hostfwd=tcp::3389-:3389 \
  -device virtio-net-pci,netdev=n0 \
  -vnc 127.0.0.1:$VNC_PORT
"

echo "Installer started."

echo "Connect VNC: 127.0.0.1:5901"
echo "Load driver: viostor > 2k22 > amd64"

echo "After install:"
echo "Shutdown Windows → then run: reboot -f"
