#!/bin/bash


if [[ $EUID -ne 0 ]]; then
    echo "You must be root to run virtual_timur"
    exit 1
fi



PATH_TO_VIRTUAL_TIMUR=/usr/local/bin/virtual_timur
PROJECT_PATH=/var/lib/virtual_timur
IMAGES_PATH=/var/lib/virtual_timur/images
MOUNTS_PATH=/var/lib/virtual_timur/mnts

DEFAULT_CONTAINER_NAME=virtual_timur
DEFAULT_BRIDGE_NAME=timur

ROOTFS_BASE_IMAGE=${IMAGES_PATH}/rootfs_base.tar



show_help(){
    echo "Usage: $0 [OPTION] [CONTAINER_NAME]"
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  init          Initialize virtual timur"
    echo "  build         Build a new container"
    echo "  run           Run a container"
    echo "  list, ls      List all containers"
    echo "  stop          Stop a container"
    echo "  rm, remove    Remove a container"
    echo "  clear         Clear all containers"
}



init_virtual_timur(){
    mkdir -p $PROJECT_PATH
    mkdir -p $IMAGES_PATH
    mkdir -p $MOUNTS_PATH
    get_default_image
    setup_isolated_iface 

    echo "Virtual Timur initialized"
}


get_default_image(){
    if [[ ! -f "$ROOTFS_BASE_IMAGE" ]]; then
        echo "Downloading rootfs base image..."
        docker pull ubuntu:latest
        local image_id=$(docker images -q ubuntu:latest)
        docker export $image_id -o "$ROOTFS_BASE_IMAGE"
        echo "Rootfs base image downloaded to $ROOTFS_BASE_IMAGE"
    else
        echo "Rootfs base image already exists."
    fi
}

setup_isolated_iface(){
    echo "Setting up isolated network interface..."
    ip netns add netns_$DEFAULT_BRIDGE_NAME
    ip link add veth_$DEFAULT_BRIDGE_NAME type veth peer name veth_br_$DEFAULT_BRIDGE_NAME
    ip link set veth_$DEFAULT_BRIDGE_NAME netns netns_$DEFAULT_BRIDGE_NAME
    ip netns exec netns_$DEFAULT_BRIDGE_NAME ip addr add 192.168.1.1/24 dev veth_$DEFAULT_BRIDGE_NAME
    ip netns exec netns_$DEFAULT_BRIDGE_NAME ip link set dev veth_$DEFAULT_BRIDGE_NAME up
    ip link set dev veth_br_$DEFAULT_BRIDGE_NAME up
}


remove_isolated_iface(){
    echo "Removing isolated network interface..."
    ip link del veth_$DEFAULT_BRIDGE_NAME
    ip netns del netns_$DEFAULT_BRIDGE_NAME
}

clear_virtual_timur (){
    echo "Clearing all virtual timur instances..."
   
    local containers=($(ls $MOUNTS_PATH))
    for container in "${containers[@]}"; do
        remove_virtual_timur $container
    done 

    echo "Virtual Timur containers cleared"

    iptables -t nat -F
    
    rm -rf $PROJECT_PATH

    remove_isolated_iface 
}


build_virtual_timur (){
    local loop_device
    local mount_point="${MOUNTS_PATH}/$2" 

    dd if=/dev/zero of="${IMAGES_PATH}/$2.img" bs=1G count=10

    loop_device=$(losetup -f --show "${IMAGES_PATH}/$2.img")

    mkfs.ext4 "$loop_device"

    mkdir -p "$mount_point"
    mount "$loop_device" "$mount_point"

    tar -xvf "$ROOTFS_BASE_IMAGE" -C "$mount_point"

    echo "stopped" > "${PROJECT_PATH}/$2.status"
}

run_virtual_timur(){
    local mount_point="${MOUNTS_PATH}/$2" 

    cgcreate -g cpu,memory:$2

    unshare --pid --mount --net --fork --mount-proc \
        chroot "$mount_point" /bin/bash -c "
        mount -t proc proc /proc &&
        mount -t sysfs sys /sys &&
        mount -o bind /dev /dev &&
        /bin/bash
    "

    echo "running" > "${PROJECT_PATH}/$2.status"

    cgexec -g cpu,memory:$2 /bin/bash
}

list_virtual_timur(){
    echo "Listing all virtual timur instances..."
    ls "${PROJECT_PATH}"/*.status
}


stop_virtual_timur(){
    local container_status_file="${PROJECT_PATH}/$2.status"
    if [[ -f "$container_status_file" ]]; then
        echo "Stopping container $2..."
        killall -s SIGTERM -g $2
        echo "stopped" > "$container_status_file"
    else
        echo "Container $2 not found."
    fi
}

remove_virtual_timur(){
    local container_status_file="${PROJECT_PATH}/$2.status"
    if [[ -f "$container_status_file" ]]; then
        stop_virtual_timur "$2"
        echo "Removing container $2..."
        local loop_device=$(losetup -j "${IMAGES_PATH}/$2.img" | cut -d: -f1)
        if [[ -n "$loop_device" ]]; then
            losetup -d "$loop_device"
        fi
        rm -rf "${MOUNTS_PATH}/$2"
        rm -f "$container_status_file"
    else
        echo "Container $2 not found."
    fi
}

case $1 in 
    "-h " | "--help") show_help ;;
    "init" ) init_virtual_timur ;;
    "build" ) build_virtual_timur "$2" ;;
    "run" ) run_virtual_timur "$2" ;;
    "list" | "ls" ) list_virtual_timur ;;
    "stop" ) stop_virtual_timur "$2" ;;
    "rm" | "remove" ) remove_virtual_timur "$2" ;;
    "clear" ) clear_virtual_timur ;;
    * ) echo "Invalid option. Use -h or --help for help." ;;
esac
