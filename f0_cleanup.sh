#!/bin/bash

my_suffix=".cpt"

set -e # exit on error

clean_container_() {
  local container_file="$1"
  if [ ! -f "$container_file" ]; then
    echo "Container file '$container_file' does not exist, skipping."
    return
  fi

  local device_name
  device_name="enc_$(echo -n "$container_file" | md5sum | cut -d' ' -f1)"
  echo "Cleaning LUKS device: $device_name"

  local mapper_dev="/dev/mapper/$device_name"
  if [ -e "$mapper_dev" ]; then
    local mount_points
    mount_points=$(mount | grep "$mapper_dev" | awk '{print $3}')
    if [ -n "$mount_points" ]; then
      while IFS= read -r mnt; do
        echo "Unmounting $mnt..."
        umount -l "$mnt" || true
      done <<< "$mount_points"
    fi
  fi

  if mountpoint -q /mnt/encrypted; then
    echo "Unmounting /mnt/encrypted..."
    umount -l /mnt/encrypted || true
  fi

  sleep 0.5

  if cryptsetup status "$device_name" >/dev/null 2>&1; then
    echo "Closing LUKS device $device_name..."
    cryptsetup luksClose "$device_name" || true
  fi

  local loopdevs
  loopdevs=$(losetup -j "$container_file" | cut -d: -f1)
  if [ -n "$loopdevs" ]; then
    for dev in $loopdevs; do
      echo "Detaching loop device $dev..."
      losetup -d "$dev" || true
    done
  fi

  if [ -d /mnt/encrypted ]; then
    rmdir /mnt/encrypted 2>/dev/null || true
  fi

  echo "Cleanup for $container_file done."
}

main_() {
  if [ $# -ne 1 ]; then
    echo "Usage: $0 <container_file${my_suffix}>"
    exit 1
  fi
  clean_container_ "$1"
}

main_ "$@"
