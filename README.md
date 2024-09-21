# RapidRaidSync

Automate your RAID 0 configuration and daily backups with ease.

## Table of Contents

- [Introduction](#introduction)
- [Use Case Scenario](#use-case-scenario)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Security Considerations](#security-considerations)
- [Important Notes](#important-notes)
- [License](#license)
---

## Introduction

**RapidRaidSync** is a powerful bash script designed to simplify and automate the process of configuring a RAID 0 array and setting up daily backups from a remote server using `rsync`. Whether you're a tech enthusiast or an IT professional, this tool enables you to efficiently manage your local backups, ensuring your data is safe and accessible.


### **Example Scenario**

Imagine you have multiple devices—phones, laptops, desktop PCs—all uploading important data to a cloud server. While the cloud server is accessible from anywhere, you want an extra layer of security by keeping a local backup.

With **RapidRaidSync**, you:

- **Set Up a Local Backup Server**: Use a spare server with multiple drives to create a high-speed RAID 0 array.
- **Automate Backups**: Schedule daily backups from your cloud server to your local server.
- **Maintain Redundancy**: Ensure that even if your cloud server is inaccessible, you have all your data locally.

This setup combines the convenience of cloud storage with the security of local backups.

---

## Use Case Scenario

In today's digital age, we rely heavily on multiple devices like smartphones, laptops, and desktop PCs. Managing backups across these devices can be challenging. Here's where **RapidRaidSync** plays a crucial role:

- **Centralized Cloud Backup**: All your end-user devices automatically upload their data to a cloud server. This server acts as the main repository accessible from anywhere.
  
- **Local Backup Solution**: Using RapidRaidSync, you set up a separate local server that pulls backups from your cloud server. This ensures that you have a local copy of all your data.

- **Redundancy and Accessibility**: By maintaining both cloud and local backups, you benefit from the accessibility of cloud storage and the security of local backups.

This script is ideal for users who want to:

- **Enhance Data Security**: Protect against data loss in case the cloud server experiences downtime or data corruption.
- **Improve Backup Efficiency**: Automate the backup process without manual intervention.
- **Optimize Storage Performance**: Leverage RAID 0 to maximize read/write speeds for large backup operations.

---

## Features

- **Automated RAID 0 Configuration**: Quickly set up a RAID 0 array with your chosen drives to maximize performance.
- **Flexible Drive Selection**: Easily select which drives to include in the RAID array, with a default option to use all available drives except the boot drive.
- **Filesystem Creation and Mounting**: Automatically formats the RAID array with `ext4` and mounts it at `/mnt/backup`.
- **Daily Automated Backups**: Creates a backup script that synchronizes data from a remote server using `rsync` and schedules it to run daily at 3 AM.
- **User-Friendly Interface**: Interactive prompts guide you through each step, making it accessible even for users with minimal experience.
- **Detailed Feedback**: Informative messages keep you updated on the script's progress, ensuring transparency and ease of use.

---

## Prerequisites

- **Operating System**: Ubuntu Server (any recent version)
- **User Privileges**: Must be run with `sudo` or as the root user
- **Network Access**: Ability to connect to the remote server via SSH/SFTP
- **Available Drives**: At least one additional drive (besides the boot drive) to include in the RAID array
- **Remote Server**: A cloud server where all end-user devices are backing up data

---

## Installation

1. **Download the Script**

   Clone the repository or download the `rapidraidsync.sh` script directly:

   ```bash
   wget https://raw.githubusercontent.com/Witteborn/RapidRaidSync/refs/heads/master/rapidraidsync.sh
   ```

2. **Make the Script Executable**

   ```bash
   chmod +x rapidraidsync.sh
   ```

---

## Usage

Run the script with `sudo`:

```bash
sudo ./rapidraidsync.sh
```

### **Script Walkthrough**

1. **Introduction**

   - The script displays an introduction explaining its purpose and actions.
   - You're prompted to press Enter to continue or Ctrl+C to abort.

2. **Installation of Required Applications**

   - The script updates the package list and installs `rsync`, `mdadm`, and `sshpass`.

3. **Drive Detection**

   - Lists all available drives and identifies the boot drive to exclude it from the RAID array.
   - By default, all other drives are selected for the RAID array.

4. **Drive Selection**

   - You can choose to accept the default selection or specify which drives to include.
   - If you choose to specify, you'll be prompted to enter the drive paths (e.g., `/dev/sdb /dev/sdc`).

5. **Confirmation and Data Loss Warning**

   - The script displays the selected drives and their sizes for confirmation.
   - **WARNING**: All data on the selected drives will be irreversibly lost.
   - You'll need to type `yes` to proceed.

6. **RAID Array Configuration**

   - Stops any existing RAID arrays on `/dev/md0` to prevent conflicts.
   - Zeroes superblocks on the selected drives.
   - Creates a RAID 0 array with the selected drives.
   - Formats the RAID array with the `ext4` filesystem.
   - Mounts the RAID array to `/mnt/backup` and updates `/etc/fstab` for automatic mounting on startup.

7. **Backup Script Setup**

   - Prompts you to enter the `rsync` source in the format `user@remote_host:/path/to/source`.
   - Prompts for the SFTP password (input will be hidden).
   - Creates the backup script at `/usr/local/bin/backup_rsync.sh`.
   - Schedules the backup script to run daily at 3 AM via cron.

8. **Completion**

   - Displays a summary of the actions taken and where you can find the backup script.



## Security Considerations

**Storing Passwords in Scripts**

- **Risk Acknowledgement**: The SFTP password is stored in plaintext within the backup script. Unauthorized access to this script could compromise your remote server's security.
- **Permissions**: The script sets strict permissions (`700`) on the backup script to restrict access to the root user.
- **Recommendations**:
  - **Access Control**: Limit server access to trusted users only.
  - **Use SSH Key Authentication**: Set up SSH key-based authentication with the remote server to eliminate the need for passwords in scripts.
    - **How to Set Up SSH Keys**:
      1. Generate an SSH key pair on your local server:
         ```bash
         ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
         ```
      2. Copy the public key to your remote server:
         ```bash
         ssh-copy-id user@remote_host
         ```
      3. Modify the backup script to use SSH keys and remove `sshpass`:
         ```bash
         rsync --delete -azP -e ssh $RSYNC_SOURCE $RSYNC_DESTINATION
         ```
  - **Regular Audits**: Periodically review file permissions and access logs.
  - **Encryption**: If storing passwords is necessary, consider using an encrypted vault or environment variables with restricted access.

---

## Important Notes

- **Data Loss Risk**:
  - **Irreversible Action**: All data on the selected drives will be **permanently erased** during the RAID configuration.
  - **Backup Important Data**: Ensure any important data on these drives is backed up before running the script.

- **RAID 0 Considerations**:
  - **No Redundancy**: RAID 0 offers increased performance but **no fault tolerance**. If any drive fails, all data in the array is lost.
  - **Use Case Suitability**: Ideal for scenarios where performance is critical and data loss is acceptable or mitigated by backups.

- **Testing the Backup Script**:
  - **Manual Execution**: Test the backup script to verify it works correctly:
    ```bash
    sudo /usr/local/bin/backup_rsync.sh
    ```
  - **Monitoring**: Check the output for errors and ensure data is properly synchronized.

- **Monitoring and Maintenance**:
  - **RAID Health**: Regularly monitor the RAID array's health using `mdadm`:
    ```bash
    sudo mdadm --detail /dev/md0
    ```
  - **Backup Verification**: Periodically verify the integrity and completeness of your backups.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Disclaimer**: Use this script at your own risk. The authors are not responsible for any data loss, security breaches, or damages that may occur from using this script. Always ensure you understand the actions being performed and consult with a professional if in doubt.
