#!/bin/bash

# Shared rclone configuration via environment variables
# Source this file to configure rclone without a rclone.conf file
#
# Requires B2_APPLICATION_KEY_ID and B2_APPLICATION_KEY to be set
# (typically loaded from server/.env)

export RCLONE_CONFIG_BACKBLAZE_TYPE=b2
export RCLONE_CONFIG_BACKBLAZE_ACCOUNT="${B2_APPLICATION_KEY_ID}"
export RCLONE_CONFIG_BACKBLAZE_KEY="${B2_APPLICATION_KEY}"
export RCLONE_CONFIG_BACKBLAZE_HARD_DELETE=false
