#!/bin/bash

# Usage: ./create_user.sh <NFS_SHARE> <USERID> <USERNAME>

# Validate input parameters
if [ $# -ne 3 ]; then
    echo "Usage: $0 <NFS_SHARE> <USERID> <USERNAME>"
    exit 1
fi

NFS_SHARE="$1"
USERID="$2"
USERNAME="$3"

# Constants
NFS_MOUNT_DIR="/awipsprofiles"
NFS_OPTIONS="vers=4,minorversion=1,sec=sys,nconnect=4"
AUTOFS_ROOT="/nfshome"
NFS_USERDIR="$NFS_MOUNT_DIR/$USERNAME"
USERHOME="$AUTOFS_ROOT/$USERNAME"

# Create mount directory if it doesn't exist
if [ ! -d "$NFS_MOUNT_DIR" ]; then
    mkdir -p "$NFS_MOUNT_DIR"
fi

# Mount NFS share
mount -t nfs "$NFS_SHARE" "$NFS_MOUNT_DIR" -o "$NFS_OPTIONS"

# Create user directory if it doesn't exist
if [ ! -d "$NFS_USERDIR" ]; then
    mkdir -p "$NFS_USERDIR"
    cp -r /etc/skel/. "$NFS_USERDIR"
fi

# Create user with specified UID and home directory
useradd -d "$USERHOME" -u "$USERID" -U "$USERNAME"

# Set ownership and permissions
chown -R "$USERNAME:$USERNAME" "$NFS_USERDIR"
chmod 700 "$NFS_USERDIR"

# Unmount NFS share
umount "$NFS_MOUNT_DIR"
