set -e

# =========================
# Paths
# =========================
VM_DIR="$HOME/qemu"
RAW_DISK="$VM_DIR/windows10.qcow2"
WIN_ISO="$VM_DIR/windows10.iso"
VIRTIO_ISO="$VM_DIR/virtio-win.iso"
NOVNC_DIR="$HOME/noVNC"

OVMF_DIR="$VM_DIR/ovmf"
OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

mkdir -p "$VM_DIR" "$OVMF_DIR"

# =========================
# Download OVMF (UEFI)
# =========================
if [ ! -f "$OVMF_CODE" ]; then
  wget -O "$OVMF_CODE" \
    https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
fi

if [ ! -f "$OVMF_VARS" ]; then
  wget -O "$OVMF_VARS" \
    https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd
fi

# =========================
# Download Windows 10 ISO
# =========================
if [ ! -f "$WIN_ISO" ]; then
  echo "Downloading Windows 10 22H2 ISO..."
  wget -O "$WIN_ISO" \
    https://archive.org/download/windows-10-22h2-english-x64/Win10_22H2_English_x64.iso
fi

# =========================
# Download VirtIO ISO
# =========================
if [ ! -f "$VIRTIO_ISO" ]; then
  wget -O "$VIRTIO_ISO" \
    https://github.com/kmille36/idx-windows-gui/releases/download/1.0/virtio-win-0.1.271.iso
fi

# =========================
# Clone noVNC
# =========================
if [ ! -d "$NOVNC_DIR/.git" ]; then
  git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
fi

# =========================
# Create Disk If Missing
# =========================
if [ ! -f "$RAW_DISK" ]; then
  echo "Creating new disk (30GB)..."
  qemu-img create -f qcow2 "$RAW_DISK" 30G
fi

# =========================
# Auto Boot Detection
# =========================
if [ -f "$RAW_DISK" ]; then
  DISK_SIZE=$(stat -c%s "$RAW_DISK")
  if [ "$DISK_SIZE" -gt 5000000000 ]; then
    echo "Windows detected → Booting from disk"
    BOOT_ORDER="c"
  else
    echo "Disk empty → Booting installer"
    BOOT_ORDER="d"
  fi
else
  echo "No disk found → Booting installer"
  BOOT_ORDER="d"
fi

# =========================
# Start QEMU
# =========================
echo "Starting Windows 10 VM..."

nohup qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -smp 4 \
  -m 8192 \
  -M q35 \
  -device usb-tablet \
  -device virtio-balloon-pci \
  -vga virtio \
  -netdev user,id=n0 \
  -device virtio-net-pci,netdev=n0 \
  -boot order=$BOOT_ORDER \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$OVMF_VARS" \
  -drive file="$RAW_DISK",format=qcow2,if=virtio \
  -cdrom "$WIN_ISO" \
  -drive file="$VIRTIO_ISO",media=cdrom,if=ide \
  -vnc :0 \
  -display none \
  > /tmp/qemu.log 2>&1 &

# =========================
# Start noVNC
# =========================
nohup "$NOVNC_DIR/utils/novnc_proxy" \
  --vnc 127.0.0.1:5900 \
  --listen 2016 \
  > /tmp/novnc.log 2>&1 &

# =========================
# Start Cloudflare Tunnel
# =========================
nohup cloudflared tunnel \
  --no-autoupdate \
  --url http://localhost:2016 \
  > /tmp/cloudflared.log 2>&1 &

sleep 8

# =========================
# Show & Save URL
# =========================
if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
  URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)

  echo "========================================="
  echo " 🌍 Windows 10 Ready:"
  echo "     $URL/vnc.html"
  echo "========================================="

  SAVE_FILE="$VM_DIR/noVNC-URL.txt"

  {
    echo "========================================="
    echo " Windows 10 VM Access"
    echo " Created: $(date)"
    echo " Boot Mode: $BOOT_ORDER"
    echo ""
    echo "$URL/vnc.html"
    echo "========================================="
  } > "$SAVE_FILE"

  echo "URL saved to: $SAVE_FILE"
else
  echo "❌ Cloudflared tunnel failed"
fi

# =========================
# Keep Workspace Alive
# =========================
while true; do sleep 99999; done
