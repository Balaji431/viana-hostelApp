#!/bin/bash

# VStay Project Cleanup Script for sharing (Mac/Linux Bash)
echo -e "\033[0;36m=== Starting Project Cleanup for Sharing ===\033[0m"

# 1. Run Flutter Clean
echo -e "\n\033[0;33m[1/3] Cleaning Flutter build caches...\033[0m"
if command -v flutter &> /dev/null; then
    flutter clean
else
    echo -e "\033[0;31mWarning: Flutter SDK not found in PATH! Skipping flutter clean.\033[0m"
fi

# 2. Perform cleanup of root-level temporary & duplicate files
echo -e "\n\033[0;33m[2/3] Deleting root-level temporary & duplicate files...\033[0m"

# Array of items to delete
items=(
    "*.log"
    "stay_simats*.sql"
    "response.json"
    "schema.sql"
    "database"
    "cleanup_payments.php"
    "fix_warden_passwords.php"
    "get_wardens_creds.php"
    "list_mapping_staff.php"
    "update_mapping_table.php"
    "update_venkatesh.php"
    "Dockerfile.android_build"
)

for item in "${items[@]}"; do
    # Find matching files/dirs using wildcard expansion safely
    for match in $item; do
        if [ -e "$match" ]; then
            rm -rf "$match"
            echo -e "  Deleted: $match"
        fi
    done
done

# 3. Success message
echo -e "\n\033[0;32m[3/3] Project directory is now fully clean!\033[0m"
echo -e "\033[0;32mYou can now zip and share the folder to run on iOS/Mac.\033[0m"
echo -e "\033[0;32m==========================================\033[0m"
