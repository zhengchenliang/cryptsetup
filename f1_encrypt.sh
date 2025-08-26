#!/bin/bash

my_suffix=".cpt"

set -e # exit on error

calculate_container_size_() {
  local file_size="$1"
  local overhead=67108864 # 64MB for LUKS and FS overhead
  local block_size=65536 # 64KB
  local total=$((file_size + overhead))
  echo $(( (total + block_size - 1) / block_size * block_size ))
}

generate_device_name_() {
  local container_file="$1"
  echo "enc_$(echo -n "$container_file" | md5sum | cut -d' ' -f1)"
}

cleanup_() {
  local device_name="$1"
  if [ -d "/mnt/encrypted" ]; then
    umount /mnt/encrypted || true
    rmdir /mnt/encrypted || true
  fi
  if cryptsetup status "$device_name" >/dev/null 2>&1; then
    cryptsetup luksClose "$device_name"
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

  local file_size
  file_size=$(stat -c %s "$input_file")
  local container_size
  container_size=$(calculate_container_size_ "$file_size")
  local block_count=$((container_size / 1024 / 1024)) # dd using MB
  if [ "$block_count" -lt 1 ]; then
    block_count=1
  fi

  dd if=/dev/zero of="$container_file" bs=1M count="$block_count" status=progress
  chmod 600 "$container_file"

  local device_name
  device_name=$(generate_device_name_ "$container_file")

  trap 'cleanup_ "$device_name"; exit 1' INT TERM EXIT

  cryptsetup \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --hash sha3-512 \
    --iter-time 2000 \
    --key-size 512 \
    --pbkdf argon2id \
    --use-urandom \
    --verify-passphrase \
    luksFormat \
    "$container_file"

  cryptsetup luksOpen "$container_file" "$device_name"

  mkfs.ext4 "/dev/mapper/$device_name"

  mkdir -p /mnt/encrypted
  mount "/dev/mapper/$device_name" /mnt/encrypted

  cp "$input_file" /mnt/encrypted/

  umount /mnt/encrypted
  cryptsetup luksClose "$device_name"

  trap - INT TERM EXIT

  echo "Encryption complete: $container_file created."
}

main_() {
  if [ $# -ne 1 ]; then
    echo "Usage: $0 <input_file>"
    exit 1
  fi
  encrypt_file_ "$1"
}

main_ "$@"
