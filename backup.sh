#!/usr/bin/bash

OMNIBUS_CONTAINER_NAME="${OMNIBUS_CONTAINER_NAME:-"omnibus"}"
OMNIBUS_SKIP_OBJECTS=${OMNIBUS_SKIP_OBJECTS:-"registry,artifacts,packages"}
OPENSSL_PASS="${OPENSSL_PASS:-"pass:mypassword_would_be_here"}"
#Also valid:
#OPENSSL_PASS="${OPENSSL_PASS:-"file:/path/to/file"}"
S3_ACCESS_KEY="${S3_ACCESS_KEY}"
S3_SECRET_KEY="${S3_SECRET_KEY}"
S3_REGION="${S3_REGION:-"us-east-1"}"
S3_ENDPOINT="${S3_ENDPOINT:-"s3.wasabisys.com"}"
S3_BUCKET="${S3_BUCKET:-"backups"}"
GITLAB_BACKUPS_DIR="${GITLAB_BACKUPS_DIR:-"/var/backups/gitlab"}"

MINIMUM_COUNT_OF_BACKUPS_TO_KEEP=14
MINIMUM_AGE_OF_BACKUP_TO_DELETE=14

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
GRAY='\033[1;90m'
NC='\033[0m' # No Color

#sleep $(( $RANDOM % 3600 ))

apt update
apt install -y rclone docker.io pv jq

function verbose() {
  printf '%b\n' "${YELLOW}${1}${NC}"
}

function debug() {
  printf '%b\n' "${GRAY}${1}${NC}"
}

function info() {
  printf '%b\n' "${GREEN}${1}${NC}"
}

function error() {
  printf '%b\n' "${RED}${1}${NC}"
}

last_incremental_success_start_time=0
last_full_success_start_time=0
last_success_start_time=0
incremental_backup=0
current_copy_exit_code=1
current_backup_result=1
current_backup_skipped=0

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
chunk_size = 64M
EOF

all_remote_objects=$(rclone --config /tmp/rclone.conf lsjson "wasabi:${S3_BUCKET}/")
printf '%s' "${all_remote_objects}" | jq
all_remote_objects_count=$(printf '%s' "${all_remote_objects}" | jq "length")
printf '%s' "${all_remote_objects_count}"
if [ "${all_remote_objects_count}" -gt "${MINIMUM_COUNT_OF_BACKUPS_TO_KEEP:-14}" ]; then
  info "More than ${MINIMUM_COUNT_OF_BACKUPS_TO_KEEP} backups exist in the remote repository.  Looking for candidates to prune."
  for (( i=0; i<$all_remote_objects_count; i++ )) do
    object_name=$(printf '%s' "${all_remote_objects}" | jq -r ".[$i].Name")
    object_date=$(printf '%s' "${object_name}" | awk 'BEGIN{FS="_"}{print $1}')
    all_remote_objects=$(printf '%s' "${all_remote_objects}" | jq ".[$i].UnixTime = ${object_date}")
  done

  old_objects=$(printf '%s' "${all_remote_objects}" | jq "[ .[] | select((.UnixTime | tonumber) > 1696280671) ]")
  old_objects_count=$(printf '%s' "${old_objects}" | jq "length")
  for (( i=0; i<$old_objects_count; i++ )) do
    object_name=$(printf '%s' "${old_objects}" | jq -r ".[$i].Name")
    object_path=$(printf '%s' "${old_objects}" | jq -r ".[$i].Path")
    object_date=$(printf '%s' "${old_objects}" | jq -r ".[$i].UnixTime")
    info "Backup '${object_name}', created "$(date -d "@${object_date}")" is more than ${MINIMUM_AGE_OF_BACKUP_TO_DELETE} days old.  It can be pruned."
    debug "rclone rm \"wasabi:${S3_BUCKET}/${object_path}\""
  done
fi
printf '%s' "${all_remote_objects}" | jq
exit

if [ $last_success_age -gt 0 ]; then
  if [ $last_full_age -lt 2419200 ]; then
    previous_backup=$(find "${GITLAB_BACKUPS_DIR}" -maxdepth 1 -mindepth 1 -name "*.tar" | grep "${last_success_start_time}" | tail -1)
    previous_backup=$(basename "${previous_backup}" | awk 'BEGIN{FS="_gitlab"}{print $1}')
    info "Starting a GitLab Incremental Backup.  PREVIOUS_BACKUP=${previous_backup}"
    docker exec "${OMNIBUS_CONTAINER_NAME}" gitlab-backup create SKIP=${OMNIBUS_SKIP_OBJECTS} INCREMENTAL=yes PREVIOUS_BACKUP=${previous_backup}; echo $? >/etc/gitlab-backups/current_exit_code;
    current_backup_result=$(cat /etc/gitlab-backups/current_exit_code)
    if [ $current_backup_result -ne 0 ]; then
      info "Starting a GitLab Full Backup due to incremental backup failure."
      docker exec "${OMNIBUS_CONTAINER_NAME}" gitlab-backup create SKIP=${OMNIBUS_SKIP_OBJECTS} ; echo $? >/etc/gitlab-backups/current_exit_code;  
    else
      incremental_backup=1
    fi
  else
    info "Starting a GitLab Full Backup."
    docker exec "${OMNIBUS_CONTAINER_NAME}" gitlab-backup create SKIP=${OMNIBUS_SKIP_OBJECTS} ; echo $? >/etc/gitlab-backups/current_exit_code;
  fi
  current_backup_result=$(cat /etc/gitlab-backups/current_exit_code)
else
  printf '%b\n' "Most recent successful backup was only $last_success_age seconds ago."
  current_backup_skipped=1
fi

# TODO: We also need the secrets files gitlab.rb and gitlab-secrets.json
docker exec "${OMNIBUS_CONTAINER_NAME}" cat /etc/gitlab/gitlab.rb >"${GITLAB_BACKUPS_DIR}/gitlab.rb"
docker exec "${OMNIBUS_CONTAINER_NAME}" cat /etc/gitlab/gitlab-secrets.json >"${GITLAB_BACKUPS_DIR}/gitlab-secrets.json"

find "${GITLAB_BACKUPS_DIR}" -maxdepth 1 -mindepth 1 -name "*.tar" > /tmp/file_list_after
IFS=$'\n' read -d '' -r -a new_files < <(diff -ruN /etc/gitlab-backups/file_list_before /tmp/file_list_after | grep -v '^\+++' | grep '^\+')

current_start_time=0
for file in "${new_files[@]}"; do
  abs_file=$(printf '%s' "${file}" | sed 's/^\+//g')
  rel_file=$(basename "${abs_file}")
  if [ ! "" == "${abs_file}" ]; then
    verbose "New file was created: ${abs_file}"
    tar --append -f "${abs_file}" "${GITLAB_BACKUPS_DIR}/gitlab.rb"
    tar --append -f "${abs_file}" "${GITLAB_BACKUPS_DIR}/gitlab-secrets.json"
    tar --list -f "${abs_file}"
    debug "pv \"${abs_file}\" | openssl enc -aes-256-cbc -md sha512 -iter 8192000 -pass [MASKED] | rclone --config /tmp/rclone.conf rcat \"wasabi:${S3_BUCKET}/${rel_file}\""
    pv "${abs_file}" | openssl enc -aes-256-cbc -md sha512 -iter 8192000 -pass "${OPENSSL_PASS}" | rclone --config /tmp/rclone.conf rcat "wasabi:${S3_BUCKET}/${rel_file}"
    current_copy_exit_code=0 #$(( TODO: $PIPESTATUS[0]??? ))

    printf '%s' "PIPESTATUS: ${PIPESTATUS[0]} ${PIPESTATUS[1]} ${PIPESTATUS[2]} ${PIPESTATUS[3]}"
    #$current_copy_exit_code=$(( $current_copy_exit_code + ${PIPESTATUS[0]} + ${PIPESTATUS[1]} + ${PIPESTATUS[2]} ))

    this_start_time=$(printf '%b' "${rel_file}" | awk 'BEGIN{FS="_"}{print $1}')
    if [ $this_start_time -gt $current_start_time ]; then
      current_start_time=$this_start_time
    fi
  fi
done

if [ $current_copy_exit_code -eq 0 ] && [ $current_backup_result -eq 0 ]; then
  if [ $incremental_backup -gt 0 ]; then
    printf '%b' "${current_start_time}" > /etc/gitlab-backups/last_incremental_success_start_time
  else
    printf '%b' "${current_start_time}" > /etc/gitlab-backups/last_full_success_start_time
  fi
  cat /tmp/file_list_after >/etc/gitlab-backups/file_list_before
  
  # TODO: cleanup local files

  # TODO: cleanup remote files
elif [ $current_backup_skipped -lt 1 ]; then
  error "Backup or upload process failed."
  sleep 1200
fi