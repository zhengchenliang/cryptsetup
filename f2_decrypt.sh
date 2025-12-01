#!/bin/bash

my_suffix=".cpt"

set -e # exit on error

generate_device_name_() {
  local container_file="$1"
  echo "enc_$(echo -n "$container_file" | md5sum | cut -d' ' -f1)"
}

cleanup_() {
  local container_file="$1"
  local device_name="$2"
  # Find loop device
  local loopdev
  loopdev=$(losetup -j "$container_file" | cut -d: -f1)
  if mountpoint -q /mnt/encrypted; then
    umount /mnt/encrypted || true
  fi
  if cryptsetup status "$device_name" >/dev/null 2>&1; then
    cryptsetup luksClose "$device_name" || true
  fi
  if [ -n "$loopdev" ]; then
    losetup -d "$loopdev" || true
  fi
}

decrypt_file_() {
  local container_file="$1"
  if [ ! -f "$container_file" ]; then
    echo "Error: Container file '$container_file' does not exist."
    exit 1
  fi

  if [[ ! "$container_file" =~ ${my_suffix}$ ]]; then
    echo "Error: Input must be a ${my_suffix} file."
    exit 1
  fi

  local output_file="${container_file%${my_suffix}}"
  if [ -f "$output_file" ]; then
    echo "Error: Output file '$output_file' already exists."
    exit 1
  fi

  local device_name
  device_name=$(generate_device_name_ "$container_file")

  trap 'cleanup_ "$device_name"; exit 1' INT TERM EXIT

  loopdev=$(losetup --find --show "$container_file")
  cryptsetup luksOpen "$loopdev" "$device_name"

  mkdir -p /mnt/encrypted
  mount "/dev/mapper/$device_name" /mnt/encrypted

  local encrypted_inner_file
  encrypted_inner_file=$(ls /mnt/encrypted | grep -v lost+found | head -n1)
  if [ -z "$encrypted_inner_file" ]; then
    echo "Error: No file found inside the container."
    cleanup_ "$container_file" "$device_name"
    exit 1
  fi
  cp "/mnt/encrypted/$encrypted_inner_file" "$output_file"

  cleanup_ "$container_file" "$device_name"

  trap - INT TERM EXIT

  echo "Decryption complete: $output_file extracted."
}

main_() {
  if [ $# -ne 1 ]; then
    echo "Usage: $0 <container_file${my_suffix}>"
    exit 1
  fi
  decrypt_file_ "$1"
}

main_ "$@"
