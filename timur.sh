#!/bin/bash

# Check if the script is run as root, exit if not
if [[ $EUID -ne 0 ]]; then
    echo "You must be root to run virtual_timur"
    exit 1
fi

# Set the paths for images and mount points
IMAGES_PATH=/var/lib/virtual_timur/images
MOUNTS_PATH=/var/lib/virtual_timur/mnts
ROOTFS_BASE_IMAGE=${IMAGES_PATH}/rootfs_base.tar

# Function to display the current status
display_status() {
    echo "Current status: $1"
}

# Create directories for images and mount points
mkdir -p $IMAGES_PATH
mkdir -p $MOUNTS_PATH
display_status "Directories created"

# Create a new image file for the container
dd if=/dev/zero of=container_fs.img bs=1G count=10

# Setup loop device for the container image
loop_device=$(losetup -fP container_fs.img)

# Format the loop device with an ext4 filesystem
mkfs.ext4 $loop_device &> /dev/null

# Mount the filesystem
mount -t ext4 $loop_device $MOUNTS_PATH
display_status "Filesystem created and mounted"

# Function to get the default image for the container
get_default_image() {
    # Check if the base image file exists
    if [[ ! -f "$ROOTFS_BASE_IMAGE" ]]; then
        # Build the image from a Dockerfile if it doesn't exist
        docker build -t ubuntu:latest .
        local image_id=$(docker images -q ubuntu:latest)
        # Export the Docker image to a tarball
        docker export $image_id -o "$ROOTFS_BASE_IMAGE"
        echo "Rootfs base image downloaded to $ROOTFS_BASE_IMAGE"
    else
        echo "Rootfs base image already exists."
    fi
}

# Get or check for the rootfs base image
get_default_image
display_status "Rootfs base image handled"

# Extract the rootfs base image to mount point
tar -xf $ROOTFS_BASE_IMAGE -C $MOUNTS_PATH > /dev/null
display_status "Rootfs base image extracted"

# Copy benchmark script to the container filesystem
cp benchmark.py ${MOUNTS_PATH}/root/benchmark.py
display_status "benchmark.py copied to container filesystem"

# Create a control group for the container
cgcreate -g cpu,memory:timur
display_status "Cgroup created"

# Execute the benchmark in a new container environment
cgexec -g cpu,memory:timur \
    unshare --pid --mount --net --fork --mount-proc \
    chroot $MOUNTS_PATH /bin/bash -c \
    "mount -t proc proc /proc &&
    mount -t sysfs sys /sys &&
    mount -o bind /dev /dev &&
    python3 /root/benchmark.py &&
    /bin/bash
    " 
display_status "benchmark.py executed in container"

# Check if the report file exists and copy it
if [ -f "${MOUNTS_PATH}/root/report.md" ]; then
    cp ${MOUNTS_PATH}/root/report.md report.md
    display_status "Result file exported"
else
    display_status "Result file not found, skipping export"
fi

# Unmount the filesystem if it's currently mounted
if mountpoint -q $MOUNTS_PATH; then
    umount $MOUNTS_PATH
    display_status "Filesystem unmounted"
else
    display_status "$MOUNTS_PATH is not mounted, skipping unmount"
fi

# Detach the loop device if it's still attached
if [ -n "$loop_device" ]; then
    losetup -d $loop_device
    display_status "Loop device detached"
else
    display_status "Loop device not found, skipping detachment"
fi

# Remove the control group if it exists
if cgget -g cpu,memory:timur &> /dev/null; then
    cgdelete -g cpu,memory:timur
    display_status "Cgroup removed"
else
    display_status "Cgroup not found, skipping removal"
fi