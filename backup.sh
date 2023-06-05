#!/usr/bin/bash

OMNIBUS_CONTAINER_NAME="${OMNIBUS_CONTAINER_NAME:-"omnibus"}"
OPENSSL_PASS="${OPENSSL_PASS:-"pass:mypassword_would_be_here"}"

#Also valid:
#OPENSSL_PASS="${OPENSSL_PASS:-"file:/path/to/file"}"

sleep $(( $$RANDOM % 3600 ))

apt install -y rclone docker.io

while true; do
  last_incremental_success_start_time=0
  last_full_success_start_time=0
  incremental_backup=0
  if [ -f /etc/gitlab-backups/last_incremental_success_start_time ]; then
    last_incremental_success_start_time=$(cat /etc/gitlab-backups/last_incremental_success_start_time)
  fi
  if [ -f /etc/gitlab-backups/last_full_success_start_time ]; then
    last_full_success_start_time=$(cat /etc/gitlab-backups/last_full_success_start_time)
  fi

  date +%s > /etc/gitlab-backups/current_start_time

  if [ $last_success_start_time -gt 0 ]; then
    docker exec omnibus gitlab-backup create INCREMENTAL=yes PREVIOUS_BACKUP=$last_success_start_time; echo $? >/etc/gitlab-backups/current_exit_code;
    incremental_backup=1
  else
    docker exec "${OMNIBUS_CONTAINER_NAME}" gitlab-backup create; echo $? >/etc/gitlab-backups/current_exit_code;
  fi

  # TODO: We also need the secrets file

  # TODO: $? isn't set at this point.  Need to load from /etc/gitlab-backups/current_exit_code
  if [ $? -eq 0 ]; then
    # pv TODO | openssl enc -aes-512-cbc -md sha512 -pass "${OPENSSL_PASS}" | rclone TODO

    if [ $? -eq 0 ]; then
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