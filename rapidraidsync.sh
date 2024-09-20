#!/bin/bash

# This script installs necessary applications, sets up a RAID array with selected drives,
# mounts it, and schedules a daily rsync backup at 3 AM.

# Inform the user about the script's purpose
echo "=========================================================="
echo "Welcome to the RAID and Backup Setup Script"
echo "=========================================================="
echo "This script will perform the following actions:"
echo "1. Install necessary applications (rsync, mdadm, sshpass)."
echo "2. Configure a RAID 0 array with selected drives."
echo "3. Format and mount the RAID array to /mnt/backup."
echo "4. Create a backup script to synchronize data from a remote server."
echo "5. Schedule the backup script to run daily at 3 AM."
echo "----------------------------------------------------------"
echo "Please ensure you have backed up any important data before proceeding."
echo "Press Enter to continue or Ctrl+C to abort."
read

# Update package list and install necessary applications
echo "Updating package list and installing required applications..."
sudo apt-get update -y
sudo apt-get install -y rsync mdadm sshpass
echo "Installation of rsync, mdadm, and sshpass completed."

# List all available drives and their sizes
echo -e "\nListing all available drives:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

# Identify the boot drive
echo -e "\nIdentifying the boot drive..."
# Find the root partition (where '/' is mounted)
ROOT_PARTITION=$(findmnt -n -o SOURCE /)
# Get the parent device of the root partition (the boot drive)
ROOT_DRIVE=$(lsblk -no PKNAME "$ROOT_PARTITION")
# Construct the boot drive path
BOOT_DRIVE="/dev/$ROOT_DRIVE"

echo "Boot drive detected as $BOOT_DRIVE"

# Find all drives of type 'disk' (whole drives), excluding the boot drive
echo "Detecting all drives excluding the boot drive..."
ALL_DRIVES=$(lsblk -dpno NAME,TYPE | grep 'disk' | awk '{print $1}')
# Exclude the boot drive from the list of drives for RAID
RAID_DRIVES=$(echo "$ALL_DRIVES" | grep -v "$BOOT_DRIVE")

# Check if there are any drives to add to the RAID
if [ -z "$RAID_DRIVES" ]; then
    echo "No additional drives found for RAID configuration. Exiting."
    exit 1
fi

# Display the drives that will be selected by default (all except boot drive)
echo -e "\nBy default, the following drives will be added to the RAID array:"
for DEVICE in $RAID_DRIVES; do
    # Get the size of the device in bytes
    SIZE=$(lsblk -dnbo SIZE "$DEVICE")
    # Convert the size to a human-readable format
    HUMAN_SIZE=$(numfmt --to=iec --suffix=B "$SIZE")
    echo "$DEVICE - $HUMAN_SIZE"
done

# Prompt the user to accept the default or enter their own selection
echo -e "\nDo you want to use the default drives for the RAID array? (yes/no)"
read USE_DEFAULT

if [ "$USE_DEFAULT" = "yes" ]; then
    # Use the default drives for the RAID array
    SELECTED_DRIVES="$RAID_DRIVES"
else
    # Show available drives again for the user's convenience
    echo -e "\nAvailable drives:"
    for DEVICE in $ALL_DRIVES; do
        SIZE=$(lsblk -dnbo SIZE "$DEVICE")
        HUMAN_SIZE=$(numfmt --to=iec --suffix=B "$SIZE")
        echo "$DEVICE - $HUMAN_SIZE"
    done

    # Prompt the user to enter the drives they want to include
    echo -e "\nEnter the drives to be used in the RAID array (e.g., /dev/sdb /dev/sdc):"
    read SELECTED_DRIVES
fi

# Confirm with the user
echo -e "\nYou have selected the following drives for the RAID array:"
for DEVICE in $SELECTED_DRIVES; do
    SIZE=$(lsblk -dnbo SIZE "$DEVICE")
    HUMAN_SIZE=$(numfmt --to=iec --suffix=B "$SIZE")
    echo "$DEVICE - $HUMAN_SIZE"
done

echo -e "\nWARNING: All data on these drives will be irreversibly lost."
echo "Do you want to proceed with configuring the RAID array? (yes/no)"
read PROCEED

if [ "$PROCEED" != "yes" ]; then
    echo "Exiting without making changes."
    exit 1
fi

# Stop any existing RAID arrays to prevent conflicts
echo -e "\nStopping any existing RAID arrays on /dev/md0 (if any)..."
sudo mdadm --stop /dev/md0

# Zero superblocks on the RAID devices to prevent mdadm warnings
echo "Zeroing superblocks on the selected drives..."
for DEVICE in $SELECTED_DRIVES; do
    sudo mdadm --zero-superblock --force "$DEVICE"
done

# Calculate the number of devices
NUM_DEVICES=$(echo "$SELECTED_DRIVES" | wc -w)

# Create the RAID 0 array
echo -e "\nCreating the RAID 0 array with the selected drives..."
sudo mdadm --create --verbose /dev/md0 --level=0 --raid-devices=$NUM_DEVICES $SELECTED_DRIVES

# Wait for RAID array to be ready
echo "Waiting for the RAID array to initialize..."
sleep 5

# Create a filesystem on the RAID array
echo "Creating ext4 filesystem on the RAID array..."
sudo mkfs.ext4 /dev/md0

# Create mount point
echo "Creating mount point at /mnt/backup..."
sudo mkdir -p /mnt/backup

# Mount the RAID array
echo "Mounting the RAID array to /mnt/backup..."
sudo mount /dev/md0 /mnt/backup

# Save mdadm configuration to mdadm.conf
echo "Saving RAID configuration to /etc/mdadm/mdadm.conf..."
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf

# Update initramfs to include the new mdadm configuration
echo "Updating initramfs to include new RAID configuration..."
sudo update-initramfs -u

# Get UUID of the RAID array
echo "Retrieving UUID of the RAID array..."
UUID=$(sudo blkid -s UUID -o value /dev/md0)

# Add entry to /etc/fstab for automatic mounting on startup
echo "Adding entry to /etc/fstab for automatic mounting..."
echo "UUID=$UUID /mnt/backup ext4 defaults,nofail,discard 0 0" | sudo tee -a /etc/fstab

# Test mounting (should mount without errors)
echo "Testing mounting of the RAID array..."
sudo mount -a

# Prompt the user for the rsync source
echo -e "\nEnter the rsync source (e.g., user@remote_host:/path/to/source):"
read RSYNC_SOURCE

# Prompt for the SFTP password (input will be hidden)
echo "Enter the password for the SFTP server (input will be hidden):"
read -s SFTP_PASSWORD

# Set the rsync destination
RSYNC_DESTINATION="/mnt/backup"

# Create the backup script
echo "Creating the backup script at /usr/local/bin/backup_rsync.sh..."
sudo tee /usr/local/bin/backup_rsync.sh > /dev/null << EOF
#!/bin/bash
# Backup script to synchronize data from the remote server to local RAID array
sshpass -p '$SFTP_PASSWORD' rsync --delete -azP -e ssh $RSYNC_SOURCE $RSYNC_DESTINATION
EOF

# Make the backup script executable and restrict permissions
echo "Setting permissions for the backup script..."
sudo chmod 700 /usr/local/bin/backup_rsync.sh

# Add the cron job to run at 3am daily, avoiding duplicate entries
echo "Scheduling the backup script to run daily at 3 AM via cron..."
( crontab -l 2>/dev/null | grep -v '/usr/local/bin/backup_rsync.sh' ; echo "0 3 * * * /usr/local/bin/backup_rsync.sh" ) | crontab -

echo -e "\n=========================================================="
echo "Setup complete!"
echo "----------------------------------------------------------"
echo "Your RAID array is configured and mounted at /mnt/backup."
echo "The rsync backup will run daily at 3 AM."
echo "You can check the backup script at /usr/local/bin/backup_rsync.sh."
echo "Please ensure that your rsync source is correct and accessible."
echo "=========================================================="
