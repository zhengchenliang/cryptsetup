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
  local mapper_dev="/dev/mapper/$device_name"
  if mountpoint -q /mnt/encrypted 2>/dev/null; then
    umount /mnt/encrypted 2>/dev/null || true
  fi
  local max_attempts=5
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    if [ -e "$mapper_dev" ]; then
      local mount_points
      mount_points=$(mount | grep "$mapper_dev" | awk '{print $3}' || true)
      if [ -n "$mount_points" ]; then
        while IFS= read -r mnt; do
          umount -l "$mnt" 2>/dev/null || true
        done <<< "$mount_points"
      fi
    fi
    if cryptsetup status "$device_name" >/dev/null 2>&1; then
      if cryptsetup luksClose "$device_name" 2>/dev/null; then
        break
      fi
    else
      break
    fi
    sleep 0.2
    attempt=$((attempt + 1))
  done
  rm -rf /mnt/encrypted 2>/dev/null || true
  local loopdevs
  loopdevs=$(losetup -j "$container_file" 2>/dev/null | cut -d: -f1 || true)
  if [ -n "$loopdevs" ]; then
    for dev in $loopdevs; do
      losetup -d "$dev" 2>/dev/null || true
    done
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

  trap 'cleanup_ "$container_file" "$device_name"; exit 1' INT TERM EXIT

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
