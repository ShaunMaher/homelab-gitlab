#!/usr/bin/bash

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
    docker exec omnibus gitlab-backup create; echo $? >/etc/gitlab-backups/current_exit_code;
  fi

  # TODO: $? isn't set at this point.  Need to load from /etc/gitlab-backups/current_exit_code
  if [ $? -eq 0 ]; then
    rclone #TODO

    if [ $? -eq 0 ]; then
      if [ $incremental_backup -gt 0 ]; then
        cat /etc/gitlab-backups/current_start_time > /etc/gitlab-backups/last_incremental_success_start_time
      else
        cat /etc/gitlab-backups/current_start_time > /etc/gitlab-backups/last_full_success_start_time
      fi
    fi
  fi
  sleep 3600
done