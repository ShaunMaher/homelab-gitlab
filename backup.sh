#!/usr/bin/bash

OMNIBUS_CONTAINER_NAME="${OMNIBUS_CONTAINER_NAME:-"omnibus"}"
OPENSSL_PASS="${OPENSSL_PASS:-"pass:mypassword_would_be_here"}"
#Also valid:
#OPENSSL_PASS="${OPENSSL_PASS:-"file:/path/to/file"}"
S3_ACCESS_KEY="${S3_ACCESS_KEY}"
S3_SECRET_KEY="${S3_SECRET_KEY}"
S3_REGION="${S3_REGION:-"us-east-1"}"
S3_ENDPOINT="${S3_ENDPOINT:-"us-east-1"}"
GITLAB_BACKUPS_DIR="${GITLAB_BACKUPS_DIR:-"/var/backups/gitlab"}"

sleep $(( $$RANDOM % 3600 ))

apt install -y rclone docker.io

while true; do
  last_incremental_success_start_time=0
  last_full_success_start_time=0
  incremental_backup=0
  if [ -f /etc/gitlab-backups/last_incremental_success_start_time ]; then
    last_incremental_success_start_time=$(cat /etc/gitlab-backups/last_incremental_success_start_time)
    #TODO: last_success_start_time
  fi
  if [ -f /etc/gitlab-backups/last_full_success_start_time ]; then
    last_full_success_start_time=$(cat /etc/gitlab-backups/last_full_success_start_time)
    #TODO: last_success_start_time
  fi

  date +%s > /etc/gitlab-backups/current_start_time

  # Write Wasabi configuration to rclone conf file
  cat <<- EOF
  [wasabi]
  env_auth = false
  access_key_id = ${S3_ACCESS_KEY}
  secret_access_key = ${S3_SECRET_KEY}
  region = "${S3_REGION}"
  endpoint = "${S3_ENDPOINT}"
  location_constraint =
  acl =
  server_side_encryption =
  storage_class =
EOF

  find "${GITLAB_BACKUPS_DIR}" > /tmp/file_list_before
  
  if [ $last_success_start_time -gt 0 ]; then
    # We pull the last_success_start_time backwards by 10 minutes just to be
    #  sure this backup and the previous backup overlap and don't miss
    #  anything.
    docker exec omnibus gitlab-backup create INCREMENTAL=yes PREVIOUS_BACKUP=$(( $last_success_start_time - 600 )); echo $? >/etc/gitlab-backups/current_exit_code;
    incremental_backup=1
  else
    docker exec "${OMNIBUS_CONTAINER_NAME}" gitlab-backup create; echo $? >/etc/gitlab-backups/current_exit_code;
  fi
  $current_backup_result=$(cat /etc/gitlab-backups/current_exit_code)

  # TODO: We also need the secrets file

  find "${GITLAB_BACKUPS_DIR}" > /tmp/file_list_after
  diff -ruN /tmp/file_list_before /tmp/file_list_after

  if [ $current_backup_result -eq 0 ]; then
    # pv TODO | openssl enc -aes-512-cbc -md sha512 -pass "${OPENSSL_PASS}" | rclone rcat wasabi:TODO
    $current_copy_exit_code=$(( TODO: $PIPESTATUS[0]??? ))

    if [ $current_copy_exit_code -eq 0 ]; then
      if [ $incremental_backup -gt 0 ]; then
        cat /etc/gitlab-backups/current_start_time > /etc/gitlab-backups/last_incremental_success_start_time
      else
        cat /etc/gitlab-backups/current_start_time > /etc/gitlab-backups/last_full_success_start_time
      fi

      # TODO: cleanup local files

      # TODO: cleanup remote files
    fi
  fi

  sleep 3600
done