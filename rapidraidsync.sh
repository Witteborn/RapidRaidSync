#!/bin/bash

# ==========================================================
# RapidRaidSync
# Automate RAID 0 configuration and daily backups using lftp
# ==========================================================

# Ensure the script is not already running
LOCKFILE="/var/run/rapidraidsync_setup.lock"

# Create lockfile if it doesn't exist and set permissions
sudo touch "$LOCKFILE"
sudo chmod 600 "$LOCKFILE"

exec 200>"$LOCKFILE"

if ! flock -n 200; then
    echo "Another instance of RapidRaidSync is already running. Exiting."
    exit 1
fi

# Optional: Ensure the lock is released on script exit
trap 'flock -u 200' EXIT

# Inform the user about the script's purpose
echo "=========================================================="
echo "Welcome to RapidRaidSync - RAID and Backup Automation Tool"
echo "=========================================================="
echo "This script will perform the following actions:"
echo "1. Install necessary applications (lftp, mdadm)."
echo "2. Configure a RAID 0 array with selected drives."
echo "3. Format and mount the RAID array to /mnt/backup."
echo "4. Create a backup script using lftp to mirror data from a remote SFTP server."
echo "5. Schedule the backup script to run daily at 3 AM."
echo "----------------------------------------------------------"
echo "Please ensure you have backed up any important data before proceeding."
echo "Press Enter to continue or Ctrl+C to abort."
read -r

# ==========================================================
# Step 1: Update Package List and Install Necessary Applications
# ==========================================================
echo "Updating package list and installing required applications..."
sudo apt-get update -y

# Install mdadm and lftp
sudo apt-get install -y mdadm lftp

echo "Installation of lftp and mdadm completed."

# ==========================================================
# Step 2: List All Available Drives
# ==========================================================
echo -e "\nListing all available drives:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

# ==========================================================
# Step 3: Identify the Boot Drive
# ==========================================================
echo -e "\nIdentifying the boot drive..."
# Find the root partition (where '/' is mounted)
ROOT_PARTITION=$(findmnt -n -o SOURCE /)
# Get the parent device of the root partition (e.g., sda)
ROOT_DRIVE=$(lsblk -no PKNAME "$ROOT_PARTITION")
# Construct the boot drive path
BOOT_DRIVE="/dev/$ROOT_DRIVE"

echo "Boot drive detected as $BOOT_DRIVE"

# ==========================================================
# Step 4: Select Drives for RAID 0 (Default: All except Boot Drive)
# ==========================================================
echo "Detecting all drives excluding the boot drive..."
ALL_DRIVES=$(lsblk -dpno NAME,TYPE | grep 'disk' | awk '{print $1}')
# Exclude the boot drive from the list of drives for RAID
RAID_DRIVES=$(echo "$ALL_DRIVES" | grep -v "$BOOT_DRIVE")

# Check if there are any drives to add to the RAID
if [ -z "$RAID_DRIVES" ]; then
    echo "No additional drives found for RAID configuration. Exiting."
    exit 1
fi

# Display the default selection
echo -e "\nBy default, the following drives will be added to the RAID array:"
for DEVICE in $RAID_DRIVES; do
    SIZE=$(lsblk -dnbo SIZE "$DEVICE")
    HUMAN_SIZE=$(numfmt --to=iec --suffix=B "$SIZE")
    echo "$DEVICE - $HUMAN_SIZE"
done

# Prompt the user to accept the default or enter their own selection
echo -e "\nDo you want to use the default drives for the RAID array? (yes/no)"
read -r USE_DEFAULT

if [ "$USE_DEFAULT" = "yes" ]; then
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
    read -r SELECTED_DRIVES

    # Validate user input
    if [ -z "$SELECTED_DRIVES" ]; then
        echo "No drives entered. Exiting."
        exit 1
    fi
fi

# Confirm the selected drives
echo -e "\nYou have selected the following drives for the RAID array:"
for DEVICE in $SELECTED_DRIVES; do
    SIZE=$(lsblk -dnbo SIZE "$DEVICE")
    HUMAN_SIZE=$(numfmt --to=iec --suffix=B "$SIZE")
    echo "$DEVICE - $HUMAN_SIZE"
done

# Warning about data loss
echo -e "\nWARNING: All data on the selected drives will be irreversibly lost."
echo "Do you want to proceed with configuring the RAID array? (yes/no)"
read -r PROCEED

if [ "$PROCEED" != "yes" ]; then
    echo "Exiting without making changes."
    exit 1
fi

# ==========================================================
# Step 5: Configure RAID 0 Array
# ==========================================================
echo -e "\nStopping any existing RAID arrays on /dev/md0 (if any)..."
sudo mdadm --stop /dev/md0 2>/dev/null

echo "Zeroing superblocks on the selected drives..."
for DEVICE in $SELECTED_DRIVES; do
    sudo mdadm --zero-superblock --force "$DEVICE"
done

# Calculate the number of devices
NUM_DEVICES=$(echo "$SELECTED_DRIVES" | wc -w)

echo "Creating the RAID 0 array with the selected drives..."
sudo mdadm --create --verbose /dev/md0 --level=0 --raid-devices="$NUM_DEVICES" $SELECTED_DRIVES

# Wait for RAID array to initialize
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

# Test mounting
echo "Testing mounting of the RAID array..."
sudo mount -a

# ==========================================================
# Step 6: Setup Backup Script Using lftp
# ==========================================================
echo -e "\nSetting up the backup configuration using lftp..."

# Prompt for SFTP server details
echo "Enter the SFTP username for the remote server:"
read -r SFTP_USER

echo "Enter the SFTP server address (e.g., remote_host.com):"
read -r SFTP_HOST

echo "Enter the SFTP password (input will be hidden):"
read -rs SFTP_PASSWORD
echo

echo "Enter the remote source directory to back up (e.g., /path/to/source):"
read -r REMOTE_SOURCE

# Set the rsync destination
LOCAL_DESTINATION="/mnt/backup"

# Create the backup script using lftp
echo "Creating the backup script at /usr/local/bin/backup_lftp.sh..."
sudo tee /usr/local/bin/backup_lftp.sh > /dev/null << EOF
#!/bin/bash
# Backup script to synchronize data from the remote SFTP server to local RAID array using lftp

# Define log file
LOG_FILE="/var/log/rapidraidsync_backup.log"

# Define remote server details
SFTP_USER="$SFTP_USER"
SFTP_PASSWORD="$SFTP_PASSWORD"
SFTP_HOST="$SFTP_HOST"
REMOTE_SOURCE="$REMOTE_SOURCE"
LOCAL_DESTINATION="$LOCAL_DESTINATION"

# Ensure only one instance runs at a time
LOCKFILE="/var/run/backup_lftp.lock"
exec 201>"\$LOCKFILE"

if ! flock -n 201; then
    echo "Backup script is already running. Exiting." >> "\$LOG_FILE"
    exit 1
fi

# Start logging
echo "==========================================" >> "\$LOG_FILE"
echo "Backup started at \$(date)" >> "\$LOG_FILE"

# Execute lftp mirror command with logging
lftp -u "\$SFTP_USER","\$SFTP_PASSWORD" sftp://"\$SFTP_HOST" <<EOF_LFTP >> "\$LOG_FILE" 2>&1
mirror --delete --continue --parallel=4 --verbose "\$REMOTE_SOURCE" "\$LOCAL_DESTINATION"
bye
EOF_LFTP

# Check exit status
if [ \$? -eq 0 ]; then
    echo "Backup completed successfully at \$(date)" >> "\$LOG_FILE"
else
    echo "Backup failed at \$(date)" >> "\$LOG_FILE"
fi

echo "==========================================" >> "\$LOG_FILE"
EOF

# Make the backup script executable and restrict permissions
echo "Setting permissions for the backup script..."
sudo chmod 700 /usr/local/bin/backup_lftp.sh

# Create the log file and set permissions
echo "Creating log file at /var/log/rapidraidsync_backup.log..."
sudo touch /var/log/rapidraidsync_backup.log
sudo chmod 600 /var/log/rapidraidsync_backup.log

# ==========================================================
# Step 7: Schedule the Backup Script with Cron
# ==========================================================
echo "Scheduling the backup script to run daily at 3 AM via cron..."
(crontab -l 2>/dev/null | grep -v '/usr/local/bin/backup_lftp.sh' ; echo "0 3 * * * /usr/local/bin/backup_lftp.sh") | crontab -

echo -e "\n=========================================================="
echo "RapidRaidSync Setup Complete!"
echo "----------------------------------------------------------"
echo "Your RAID array is configured and mounted at /mnt/backup."
echo "The lftp backup script is located at /usr/local/bin/backup_lftp.sh."
echo "Backup logs can be found at /var/log/rapidraidsync_backup.log."
echo "Backups will run daily at 3 AM."
echo "Please ensure that your SFTP source details are correct and accessible."
echo "=========================================================="
