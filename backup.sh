#!/usr/bin/bash

OMNIBUS_CONTAINER_NAME="${OMNIBUS_CONTAINER_NAME:-"omnibus"}"
OPENSSL_PASS="${OPENSSL_PASS:-"pass:mypassword_would_be_here"}"
#Also valid:
#OPENSSL_PASS="${OPENSSL_PASS:-"file:/path/to/file"}"
S3_ACCESS_KEY="${S3_ACCESS_KEY}"
S3_SECRET_KEY="${S3_SECRET_KEY}"
S3_REGION="${S3_REGION:-"us-east-1"}"
S3_ENDPOINT="${S3_ENDPOINT:-"s3.wasabisys.com"}"
S3_BUCKET="${S3_BUCKET:-"backups"}"
GITLAB_BACKUPS_DIR="${GITLAB_BACKUPS_DIR:-"/var/backups/gitlab"}"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
GRAY='\033[1;90m'
NC='\033[0m' # No Color

#sleep $(( $RANDOM % 3600 ))

apt install -y rclone docker.io pv

function verbose() {
  printf '%b\n' "${YELLOW}${1}${NC}"
}

function debug() {
  printf '%b\n' "${GRAY}${1}${NC}"
}

function info() {
  printf '%b\n' "${GREEN}${1}${NC}"
}

while true; do
  last_incremental_success_start_time=0
  last_full_success_start_time=0
  last_success_start_time=0
  incremental_backup=0
  current_copy_exit_code=0

  # Load the timestamps of the most recent successful backups
  if [ -f /etc/gitlab-backups/last_incremental_success_start_time ]; then
    last_incremental_success_start_time=$(cat /etc/gitlab-backups/last_incremental_success_start_time)
  fi
  if [ -f /etc/gitlab-backups/last_full_success_start_time ]; then
    last_full_success_start_time=$(cat /etc/gitlab-backups/last_full_success_start_time)
  fi

  # The most recent backup of any type is the last_success_start_time
  if [ $last_full_success_start_time -gt $last_incremental_success_start_time ]; then
    last_success_start_time=$last_full_success_start_time
  else
    last_success_start_time=$last_incremental_success_start_time
  fi
  last_success_age=$(( $(date +%s) - $last_success_start_time ))
  last_full_age=$(( $(date +%s) - $last_full_success_start_time ))

  debug "last_full_success_start_time: $last_full_success_start_time"
  debug "last_incremental_success_start_time: $last_incremental_success_start_time"
  debug "last_success_start_time: $last_success_start_time"
  debug "last_success_age: $last_success_age"
  date +%s > /etc/gitlab-backups/current_start_time

  # Write Wasabi configuration to rclone conf file
  cat >/tmp/rclone.conf <<- EOF
[wasabi]
type = s3
provider = Wasabi
env_auth = false
access_key_id = ${S3_ACCESS_KEY}
secret_access_key = ${S3_SECRET_KEY}
region = ${S3_REGION}
endpoint = ${S3_ENDPOINT}
location_constraint =
acl =
server_side_encryption =
storage_class =
no_check_bucket = true
EOF

  find "${GITLAB_BACKUPS_DIR}" > /tmp/file_list_before
  
  if [ $last_success_age -gt 86400 ]; then
    if [ $last_full_age -lt 2419200 ]; then # 4 weeks
      # We pull the last_success_start_time backwards by 10 minutes just to be
      #  sure this backup and the previous backup overlap and don't miss
      #  anything.
      info "Starting a GitLab Incremental Backup.  PREVIOUS_BACKUP=$(( $last_success_start_time - 600 ))"
      docker exec "${OMNIBUS_CONTAINER_NAME}" gitlab-backup create SKIP=registry,artifacts,packages INCREMENTAL=yes PREVIOUS_BACKUP=$(( $last_success_start_time - 600 )); echo $? >/etc/gitlab-backups/current_exit_code;
      incremental_backup=1
    else
      info "Starting a GitLab Full Backup."
      docker exec "${OMNIBUS_CONTAINER_NAME}" gitlab-backup create SKIP=registry,artifacts,packages ; echo $? >/etc/gitlab-backups/current_exit_code;
    fi
    current_backup_result=$(cat /etc/gitlab-backups/current_exit_code)
  else
    printf '%b\n' "Most recent successful backup was only $last_success_age seconds ago."
    current_backup_result=$(cat /etc/gitlab-backups/current_exit_code)
  fi

  # TODO: We also need the secrets files gitlab.rb and gitlab-secrets.json

  find "${GITLAB_BACKUPS_DIR}" > /tmp/file_list_after
  IFS=$'\n' read -d '' -r -a new_files < <(diff -ruN /tmp/file_list_before /tmp/file_list_after | grep -v '^\+++' | grep '^\+')

  if [ $current_backup_result -eq 0 ]; then
    for file in "${new_files[@]}"; do
      abs_file=$(printf '%s' "${file}" | sed 's/^\+//g')
      rel_file=$(basename "${abs_file}")
      if [ ! "" == "${file}" ]; then
        verbose "New file was created: ${file}"
        debug "pv \"${abs_file}\" | openssl enc -aes-256-cbc -md sha512 -iter 8192000 -pass \"${OPENSSL_PASS}\" | rclone --config /tmp/rclone.conf rcat \"wasabi:${S3_BUCKET}/${rel_file}\""
        pv "${abs_file}" | openssl enc -aes-256-cbc -md sha512 -iter 8192000 -pass "${OPENSSL_PASS}" | rclone --config /tmp/rclone.conf rcat "wasabi:${S3_BUCKET}/${rel_file}"
        current_copy_exit_code=0 #$(( TODO: $PIPESTATUS[0]??? ))
      fi
    done

    if [ $current_copy_exit_code -eq 0 ]; then
      if [ $incremental_backup -gt 0 ]; then
        cat /etc/gitlab-backups/current_start_time > /etc/gitlab-backups/last_incremental_success_start_time
      else
        cat /etc/gitlab-backups/current_start_time > /etc/gitlab-backups/last_full_success_start_time
      fi

      # TODO: cleanup local files

      # TODO: cleanup remote files
    else
      error "Backup process failed.  Not uploading files."
    fi
  fi

  info "Backup process complete.  Will now take a nap."
  sleep 3600
done