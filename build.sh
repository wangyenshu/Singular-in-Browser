#!/bin/bash

# Exit immediately if any command fails
set -e

# --- Configuration ---
IMAGE_NAME="singular-32bit"
OUTPUT_FILE="singular_32bit.ext2"
MOUNT_DIR="./temp_mount_point"
SPLIT_SIZE="20M"

# Build the image using the current directory's Dockerfile
docker build -t "$IMAGE_NAME" .

# Get the uncompressed size of the image in bytes
IMG_SIZE_BYTES=$(docker inspect -f "{{ .Size }}" "$IMAGE_NAME")
# Convert to MB and add 50MB safety buffer for inodes/metadata
IMG_SIZE_MB=$((IMG_SIZE_BYTES / 1024 / 1024 + 50))

echo "Docker Image Size: $((IMG_SIZE_BYTES / 1024 / 1024)) MB"
echo "Target Ext2 Size:  $IMG_SIZE_MB MB (includes safety buffer)"

# Create an empty file of the calculated size filled with zeros
dd if=/dev/zero of="$OUTPUT_FILE" bs=1M count="$IMG_SIZE_MB" status=progress

# Format the file as ext2 (-F forces it to run on a file)
mkfs.ext2 -F "$OUTPUT_FILE"

# Create a temporary container
CONTAINER_ID=$(docker create "$IMAGE_NAME")

# Create mount point
mkdir -p "$MOUNT_DIR"

echo "Mounting $OUTPUT_FILE"
# Mount the ext2 file to the temp directory
sudo mount -o loop "$OUTPUT_FILE" "$MOUNT_DIR"

echo "Extracting container filesystem..."
# Export the container contents and pipe them directly into the mounted folder
docker export "$CONTAINER_ID" | sudo tar -x -C "$MOUNT_DIR"

echo "Unmounting..."
sudo umount "$MOUNT_DIR"

# Cleanup
rmdir "$MOUNT_DIR"
docker rm "$CONTAINER_ID"

# Split the file into parts
split -b "$SPLIT_SIZE" "$OUTPUT_FILE" "${OUTPUT_FILE}.part"

# Rename to .part1, .part2...
i=1
for f in "${OUTPUT_FILE}.part"* ; do
    mv "$f" "${OUTPUT_FILE}.part$i"
    echo "Created ${OUTPUT_FILE}.part$i"
    ((i++))
done

# Remove the original large file to save space
rm "$OUTPUT_FILE"

echo "Done! Created the following files:"
ls -lh ${OUTPUT_FILE}.part*
