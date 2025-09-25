#!/bin/bash

my_suffix=".cpt"

set -e # exit on error

calculate_container_size_() {
  local file_size="$1"
  # Increased overhead for LUKS2 + ext4 filesystem + journal + safety margin
  # LUKS2 header: ~16MB
  # ext4 metadata: ~5% of total size
  # Journal: default 4096 blocks * 4KB = 16MB
  # Safety margin: 20% additional space
  local base_overhead=134217728 # 128MB base overhead
  local percentage_overhead=$((file_size / 5)) # 20% of file size
  local total_overhead=$((base_overhead + percentage_overhead))
  local total_size=$((file_size + total_overhead))

  local mb_size=$(( (total_size + 1048575) / 1048576 )) # round to MB
  echo $((mb_size * 1048576))
}

generate_device_name_() {
  local container_file="$1"
  echo "enc_$(echo -n "$container_file" | md5sum | cut -d' ' -f1)"
}

cleanup_() {
  local device_name="$1"
  echo "Cleaning up..."
  if mountpoint -q /mnt/encrypted 2>/dev/null; then
    umount /mnt/encrypted || umount -f /mnt/encrypted || true
  fi
  if cryptsetup status "$device_name" >/dev/null 2>&1; then
    cryptsetup luksClose "$device_name" || true
  fi
  if [ -d "/mnt/encrypted" ]; then
    rm -rf /mnt/encrypted 2>/dev/null || true
  fi
}

encrypt_file_() {
  local input_file="$1"
  if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' does not exist."
    exit 1
  fi
  local container_file="${input_file}${my_suffix}"
  if [ -f "$container_file" ]; then
    echo "Error: Container file '$container_file' already exists."
    exit 1
  fi

  echo "Calculating required space..."
  local file_size
  file_size=$(stat -c %s "$input_file")

  echo "Input file size: $((file_size / 1048576)) MB"
  local container_size
  container_size=$(calculate_container_size_ "$file_size")
  local mb_count=$((container_size / 1048576))

  echo "Creating container of size: ${mb_count} MB"
  dd if=/dev/zero of="$container_file" bs=1M count="$mb_count" status=progress
  chmod 600 "$container_file"

  local device_name
  device_name=$(generate_device_name_ "$container_file")

  trap 'cleanup_ "$device_name"; exit 1' INT TERM EXIT

  echo "Setting up LUKS encryption..."
  cryptsetup \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --hash sha3-512 \
    --iter-time 10000 `# 10000 ms` \
    --key-size 512 \
    --pbkdf argon2id \
    --use-urandom \
    --verify-passphrase \
    luksFormat \
    "$container_file"

  echo "Opening encrypted container..."
  cryptsetup luksOpen "$container_file" "$device_name"

  echo "Creating filesystem..."
  mkfs.ext4 -m 1 "/dev/mapper/$device_name"

  echo "Mounting filesystem..."
  mkdir -p /mnt/encrypted
  mount "/dev/mapper/$device_name" /mnt/encrypted

  echo "Copying file..."
  local available_space
  available_space=$(df /mnt/encrypted | tail -1 | awk '{print $4}')
  local required_space=$((file_size / 1024)) # MB to KB
  if [ "$available_space" -lt "$required_space" ]; then
    echo "Error: Not enough space in container. Available: ${available_space}KB, Required: ${required_space}KB"
    cleanup_ "$device_name"
    rm -f "$container_file"
    exit 1
  fi
  cp "$input_file" /mnt/encrypted/
  sync

  echo "Unmounting and closing..."
  trap - INT TERM EXIT
  cleanup_ "$device_name"
  echo "Encryption complete: $container_file created."
  echo "Container size: ${mb_count} MB"
  echo "Original file size: $((file_size / 1048576)) MB"
}

main_() {
  if [ $# -ne 1 ]; then
    echo "Usage: $0 <input_file>"
    exit 1
  fi
  if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges. Please run with sudo."
    exit 1
  fi
  encrypt_file_ "$1"
}

main_ "$@"
