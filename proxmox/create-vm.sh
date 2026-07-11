#!/usr/bin/env bash
# Run this ON THE PROXMOX HOST (node shell, or SSH to the node as root).
# Creates an Ubuntu 24.04 cloud-init VM to host the game-server stack.
# The game servers run INSIDE this VM — never on the Proxmox host OS directly.
set -euo pipefail

# ─────────────────── EDIT THESE ───────────────────
VMID=110
VMNAME=gameservers
CORES=4
MEMORY=12288                 # MiB (12 GB). Use 16384 for a full/busy server.
DISK_SIZE=50G
STORAGE=local-lvm            # storage for the VM disk + cloud-init drive
BRIDGE=vmbr0
IPCONFIG="ip=dhcp"           # static example: "ip=192.168.1.50/24,gw=192.168.1.1"
CIUSER=ubuntu
SSH_KEYFILE=/root/id_ed25519.pub   # YOUR public key, present on the Proxmox host
# ───────────────────────────────────────────────────

IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMG="/root/noble-server-cloudimg-amd64.img"

echo "==> Fetching Ubuntu 24.04 cloud image (if missing)"
[ -f "$IMG" ] || wget -qO "$IMG" "$IMG_URL"

echo "==> Creating VM $VMID ($VMNAME)"
qm create "$VMID" \
  --name "$VMNAME" \
  --cores "$CORES" --cpu host \
  --memory "$MEMORY" --balloon 0 \
  --net0 "virtio,bridge=$BRIDGE" \
  --scsihw virtio-scsi-single \
  --scsi0 "$STORAGE:0,import-from=$IMG,discard=on,ssd=1" \
  --ide2 "$STORAGE:cloudinit" \
  --ostype l26 \
  --agent enabled=1 \
  --boot order=scsi0 \
  --serial0 socket --vga serial0

echo "==> Cloud-init: user + SSH key + network"
qm set "$VMID" --ciuser "$CIUSER" --sshkeys "$SSH_KEYFILE" --ipconfig0 "$IPCONFIG"

echo "==> Growing root disk to $DISK_SIZE"
qm resize "$VMID" scsi0 "$DISK_SIZE"

echo "==> Starting VM"
qm start "$VMID"

echo
echo "VM $VMID started. Once the guest agent is up, find its IP with:"
echo "  qm guest cmd $VMID network-get-interfaces"
echo "Then:  ssh $CIUSER@<vm-ip>  and run  proxmox/bootstrap-vm.sh"
