{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.qemu
    pkgs.htop
    pkgs.cloudflared
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.wget
    pkgs.git
    pkgs.python3
  ];

  idx.workspace.onStart = {
    windows = ''
      set -e

      ########################
      # CONFIG (BISA DIUBAH)
      ########################

      ISO_URL="https://archive.org/download/win-11.-pro.-24-h-2.-u-8.-x-64.-wpe_202502/WIN11.PRO.24H2.U8.X64.%28WPE%29.ISO"
      ISO_FILE="$HOME/windows-idx/win11-custom.iso"

      DISK_FILE="$HOME/windows-idx/win11.qcow2"
      DISK_SIZE="11G"

      RAM="28G"
      CORES="4"

      FLAG_FILE="$HOME/windows-idx/installed.flag"
      WORKDIR="$HOME/windows-idx"
      NOVNC_DIR="$HOME/noVNC"

      ########################
      # PREPARE
      ########################

      mkdir -p "$WORKDIR"
      cd "$WORKDIR"

      # Create disk jika belum ada
      if [ ! -f "$DISK_FILE" ]; then
        echo "Creating disk $DISK_SIZE..."
        qemu-img create -f qcow2 "$DISK_FILE" "$DISK_SIZE"
      fi

      # Download ISO jika belum install
      if [ ! -f "$FLAG_FILE" ]; then
        if [ ! -f "$ISO_FILE" ]; then
          echo "Downloading Windows ISO..."
          wget --no-check-certificate -O "$ISO_FILE" "$ISO_URL"
        fi
      fi

      ########################
      # Clone noVNC
      ########################

      if [ ! -d "$NOVNC_DIR/.git" ]; then
        echo "Cloning noVNC..."
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      ########################
      # START QEMU
      ########################

      if [ ! -f "$FLAG_FILE" ]; then
        echo "⚠️ INSTALL MODE"

        nohup qemu-system-x86_64 \
          -enable-kvm \
          -cpu host \
          -smp "$CORES" \
          -m "$RAM" \
          -machine q35 \
          -drive file="$DISK_FILE",format=qcow2 \
          -cdrom "$ISO_FILE" \
          -boot order=d \
          -netdev user,id=n0,hostfwd=tcp::3389-:3389 \
          -device e1000,netdev=n0 \
          -vnc :0 \
          -display none \
          > /tmp/qemu.log 2>&1 &

      else
        echo "✅ NORMAL BOOT MODE"

        nohup qemu-system-x86_64 \
          -enable-kvm \
          -cpu host \
          -smp "$CORES" \
          -m "$RAM" \
          -machine q35 \
          -drive file="$DISK_FILE",format=qcow2 \
          -boot order=c \
          -netdev user,id=n0,hostfwd=tcp::3389-:3389 \
          -device e1000,netdev=n0 \
          -vnc :0 \
          -display none \
          > /tmp/qemu.log 2>&1 &
      fi

      ########################
      # START noVNC
      ########################

      nohup "$NOVNC_DIR/utils/novnc_proxy" \
        --vnc 127.0.0.1:5900 \
        --listen 8888 \
        > /tmp/novnc.log 2>&1 &

      ########################
      # START CLOUDFLARE
      ########################

      nohup cloudflared tunnel \
        --no-autoupdate \
        --url http://localhost:8888 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 10

      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)

        echo "====================================="
        echo "🌍 Windows ready:"
        echo "$URL/vnc.html"
        echo "====================================="

        # Simpan URL ke file
        mkdir -p /home/user/idx-windows-gui
        echo "$URL/vnc.html" > /home/user/idx-windows-gui/noVNC-URL.txt

      else
        echo "❌ Cloudflare tunnel failed"
      fi

      ########################
      # KEEP WORKSPACE ALIVE
      ########################

      while true; do
        sleep 60
      done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      windows = {
        manager = "web";
        command = [
          "bash" "-lc"
          "echo 'Windows running via noVNC (port 8888)'"
        ];
      };
    };
  };
}
