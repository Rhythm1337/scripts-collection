app-backup.sh
#!/bin/bash

# Configuration
BACKUP_DIR="/tmp/app_backups"
BACKUP_NAME="app_backup_$(date +%Y-%m-%d_%H-%M).tar.gz"
REMOTE="gdrive-accountname:app-website-backups"
LOG_FILE="/var/log/app_backup.log"
RETENTION_DAYS=7

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Start logging
{
    echo "-----------------------------------------"
    echo "Backup started at $(date)"

    # Save PM2 process state
    echo "Saving PM2 process list..."
    pm2 save || { echo "PM2 save failed"; exit 1; }

    # Verify .pm2 exists
    echo "Checking .pm2 directory contents..."
    ls -la /root/.pm2 || echo ".pm2 directory missing!"

    # Compress the directories with tar -C for better structure
    echo "Compressing directories..."
    tar -czvf "$BACKUP_DIR/$BACKUP_NAME" \
        -C /root app \
        -C /var/www app \
        -C /root .pm2

    # Check if compression was successful
    if [[ $? -eq 0 ]]; then
        echo "Compression successful: $BACKUP_DIR/$BACKUP_NAME"
    else
        echo "Compression failed!" >&2
        exit 1
    fi

    # Upload to Google Drive
    echo "Uploading $BACKUP_NAME to Google Drive..."
    rclone copy "$BACKUP_DIR/$BACKUP_NAME" "$REMOTE"

    if [[ $? -eq 0 ]]; then
        echo "Upload successful."
    else
        echo "Upload failed!" >&2
        exit 1
    fi

    # Delete backups older than X days from Google Drive
    echo "Deleting backups older than $RETENTION_DAYS days from Google Drive..."
    rclone delete --min-age "${RETENTION_DAYS}d" "$REMOTE"

    if [[ $? -eq 0 ]]; then
        echo "Old backups deleted successfully."
    else
        echo "Failed to delete old backups!" >&2
        exit 1
    fi

    # Clear Google Drive Trash
    echo "Clearing Google Drive trash..."
    rclone cleanup "$REMOTE"

    if [[ $? -eq 0 ]]; then
        echo "Google Drive trash cleared successfully."
    else
        echo "Failed to clear Google Drive trash!" >&2
    fi

    # Cleanup local backup
    echo "Cleaning up local backup..."
    rm -f "$BACKUP_DIR/$BACKUP_NAME"

    echo "Backup completed at $(date)"
    echo "-----------------------------------------"
} >> "$LOG_FILE" 2>&1
