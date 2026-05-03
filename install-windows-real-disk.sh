#!/usr/bin/env bash
set -euo pipefail

# FULL Linux -> Windows installer using QEMU on REAL DISK
# WARNING: THIS WILL WIPE LINUX

ISO_LIST=(
"http://microsoft.windowsmirrors.net/Server%202025/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
)

VIRTIO_ISO_URL="https://fedora-virt.repo.nfrance.com/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

WORKDIR="/root/win-install"
WINDOWS_ISO="$WORKDIR/windows.iso"
VIRTIO_ISO="$WORKDIR/virtio-win.iso"

RAM_MB="4096"
CPU_CORES="2"
VNC_PORT="1"

echo "================================================="
echo " FULL WINDOWS INSTALL - THIS WILL WIPE LINUX"
echo "================================================="

if [[ $EUID -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

DISK="$(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print "/dev/"$1; exit}')"

if [[ -z "$DISK" ]]; then
  echo "Could not detect disk."
  exit 1
fi

echo "Detected disk: $DISK"
echo "Type YES to continue:"
read -r CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
  echo "Cancelled."
  exit 1
fi

echo "[1] Installing packages..."

if command -v apt >/dev/null 2>&1; then
  apt update
  apt install -y qemu-system-x86 qemu-utils wget curl screen
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache qemu-system-x86_64 qemu-img wget curl screen
else
  echo "Unsupported distro. Use Ubuntu or Alpine."
  exit 1
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[2] Checking Windows ISO..."

if [[ -f "$WINDOWS_ISO" && $(stat -c%s "$WINDOWS_ISO") -gt 1000000000 ]]; then
  echo "Windows ISO already exists, skipping download."
else
  echo "Downloading Windows ISO..."

  SUCCESS=0

  for ISO in "${ISO_LIST[@]}"; do
    echo "Trying: $ISO"

    if wget -c -O "$WINDOWS_ISO" "$ISO"; then
      SUCCESS=1
      break
    else
      echo "Failed, trying next..."
      rm -f "$WINDOWS_ISO"
    fi
  done

  if [[ $SUCCESS -ne 1 ]]; then
    echo "All Windows ISO downloads failed."
    exit 1
  fi
fi

echo "[3] Checking VirtIO ISO..."

if [[ -f "$VIRTIO_ISO" && $(stat -c%s "$VIRTIO_ISO") -gt 100000000 ]]; then
  echo "VirtIO ISO already exists, skipping download."
else
  echo "Downloading VirtIO ISO..."

  if ! wget -c -O "$VIRTIO_ISO" "$VIRTIO_ISO_URL"; then
    echo "VirtIO download failed."
    rm -f "$VIRTIO_ISO"
    exit 1
  fi
fi

echo "[4] Disabling swap..."
swapoff -a || true

echo "[5] Starting Windows installer..."
echo
echo "From PowerShell on your PC, run:"
echo "ssh -L 5901:127.0.0.1:5901 root@23.230.139.250"
echo
echo "Then open VNC Viewer to:"
echo "127.0.0.1:5901"
echo
echo "When Windows asks for disk driver:"
echo "Load driver > VirtIO CD > viostor > 2k25/amd64 or 2k22/amd64"
echo

screen -S wininstall -dm bash -c "
qemu-system-x86_64 \
  -enable-kvm \
  -m $RAM_MB \
  -smp $CPU_CORES \
  -cpu host \
  -drive file=$DISK,format=raw,if=virtio,cache=none \
  -cdrom $WINDOWS_ISO \
  -drive file=$VIRTIO_ISO,media=cdrom \
  -boot d \
  -netdev user,id=n0,hostfwd=tcp::3389-:3389 \
  -device virtio-net-pci,netdev=n0 \
  -vnc 127.0.0.1:$VNC_PORT
"

echo "Windows installer started."
echo
echo "Attach console:"
echo "screen -r wininstall"
echo
echo "Detach:"
echo "CTRL + A, then D"
echo
echo "After Windows finishes:"
echo "1. Shut down Windows from installer/VNC."
echo "2. Run:"
echo "   reboot -f"
echo
echo "Then try RDP:"
echo "23.230.139.250:3389"
