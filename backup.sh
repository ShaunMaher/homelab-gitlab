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

MINIMUM_COUNT_OF_BACKUPS_TO_KEEP="${MINIMUM_COUNT_OF_BACKUPS_TO_KEEP:-14}"
MINIMUM_AGE_OF_BACKUP_TO_DELETE="${MINIMUM_AGE_OF_BACKUP_TO_DELETE:-1209600}" # 14 days
#MINIMUM_AGE_OF_BACKUP_TO_DELETE="${MINIMUM_AGE_OF_BACKUP_TO_DELETE:-3600}" # 1 hour
minimum_timestamp_of_backup=$(( $(date +%s) - $MINIMUM_AGE_OF_BACKUP_TO_DELETE ))

#sleep $(( $RANDOM % 3600 ))

# These are not used by the relevant functions yet
VERBOSE="${VERBOSE:-"/dev/stderr"}"
DEBUG="${DEBUG:-"/dev/stderr"}"
INFO="${INFO:-"/dev/stdout"}"
ERROR="${ERROR:-"/dev/stderr"}"

ANSI_COLOUR_RED='\033[1;31m'
ANSI_COLOUR_GREEN='\033[1;32m'
ANSI_COLOUR_YELLOW='\033[1;33m'
ANSI_COLOUR_GRAY='\033[1;90m'

ANSI_COLOUR_NO_COLOUR='\033[0m'
ANSI_COLOUR_ERROR="${ANSI_COLOUR_RED:-'\033[1;31m'}"
ANSI_COLOUR_INFO="${ANSI_COLOUR_GREEN:-'\033[1;31m'}"
ANSI_COLOUR_VERBOSE="${ANSI_COLOUR_YELLOW:-'\033[1;31m'}"
ANSI_COLOUR_DEBUG="${ANSI_COLOUR_GRAY:-'\033[1;31m'}"

__OUTER_STDIN_NAME=$(readlink -f /dev/stdin)


function verbose() {
  # Every method I could find that tries to work out if we are receiving data
  # on stdin always seems to return true inside a GitLab runner.  I don't know
  # why.  The following tests to see if there is a /dev/stdin AND that
  # /dev/stdin is NOT the same as the /dev/stdin passed to the entire script.
  if [[ -p /dev/stdin ]] && [ $(readlink -f /dev/stdin) != "${__OUTER_STDIN_NAME}" ]; then
    while IFS= read -r LINE; do
      printf "${ANSI_COLOUR_VERBOSE}%s${ANSI_COLOUR_NO_COLOUR}\n" "${1}${LINE}"
    done < <(cat </dev/stdin)
  elif [ ${#1} -gt 0 ]; then
    printf "${ANSI_COLOUR_VERBOSE}%s${ANSI_COLOUR_NO_COLOUR}\n" "${1}"
  fi
}

function debug() {
  if [[ -p /dev/stdin ]] && [ $(readlink -f /dev/stdin) != "${__OUTER_STDIN_NAME}" ]; then
    while IFS= read -r LINE; do
      printf "${ANSI_COLOUR_DEBUG}%s${ANSI_COLOUR_NO_COLOUR}\n" "${1}${LINE}"
    done < <(cat </dev/stdin)
  elif [ ${#1} -gt 0 ]; then
    printf "${ANSI_COLOUR_DEBUG}%s${ANSI_COLOUR_NO_COLOUR}\n" "${1}"
  fi
}

function info() {
  if [[ -p /dev/stdin ]] && [ $(readlink -f /dev/stdin) != "${__OUTER_STDIN_NAME}" ]; then
    while IFS= read -r LINE; do
      printf "${ANSI_COLOUR_INFO}%s${ANSI_COLOUR_NO_COLOUR}\n" "${1}${LINE}"
    done < <(cat </dev/stdin)
  elif [ ${#1} -gt 0 ]; then
    printf "${ANSI_COLOUR_INFO}%s${ANSI_COLOUR_NO_COLOUR}\n" "${1}"
  fi
}

function error() {
  if [[ -p /dev/stdin ]] && [ $(readlink -f /dev/stdin) != "${__OUTER_STDIN_NAME}" ]; then
    while IFS= read -r LINE; do
      if [ $(printf '%s' "${LINE}" | grep -c -i 'WARN') -gt 0 ]; then
        printf "${ANSI_COLOUR_VERBOSE}%s${ANSI_COLOUR_NO_COLOUR}\n" "${1}${LINE}"
      elif [ ${#LINE} -lt 1 ]; then
        printf "${ANSI_COLOUR_DEBUG}%s${ANSI_COLOUR_NO_COLOUR}\n" "${1}${LINE}"
      elif [ $(printf '%b' "${LINE}" | grep -c -i 'NOTICE') -gt 0 ]; then
        printf "${ANSI_COLOUR_DEBUG}%s${ANSI_COLOUR_NO_COLOUR}\n" "${1}${LINE}"
      else
        printf "${ANSI_COLOUR_ERROR}%s${ANSI_COLOUR_NO_COLOUR}\n" "${1}${LINE}"
      fi
    done < <(cat </dev/stdin)
  elif [ ${#1} -gt 0 ]; then
    printf "${ANSI_COLOUR_ERROR}%s${ANSI_COLOUR_NO_COLOUR}\n" "${1}"
  fi
}

function ltrim() {
  if [[ -p /dev/stdin ]] && [ $(readlink -f /dev/stdin) != "${__OUTER_STDIN_NAME}" ]; then
    while IFS= read -r LINE; do
      printf '%s' "${LINE}" | sed -e 's/^[[:space:]]*//'
    done < <(cat </dev/stdin)
  elif [ ${#1} -gt 0 ]; then
    printf '%s' "${1}" | sed -e 's/^[[:space:]]*//'
  fi
}

function rtrim() {
  if [[ -p /dev/stdin ]] && [ $(readlink -f /dev/stdin) != "${__OUTER_STDIN_NAME}" ]; then
    while IFS= read -r LINE; do
      printf '%s' "${LINE}" | sed -e 's/[[:space:]]*$//'
    done < <(cat </dev/stdin)
  elif [ ${#1} -gt 0 ]; then
    printf '%s' "${1}" | sed -e 's/[[:space:]]*$//'
  fi
}

function trim() {
  if [[ -p /dev/stdin ]] && [ $(readlink -f /dev/stdin) != "${__OUTER_STDIN_NAME}" ]; then
    while IFS= read -r LINE; do
      printf '%s' "${LINE}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    done < <(cat </dev/stdin)
  elif [ ${#1} -gt 0 ]; then
    printf '%s' "${1}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
  fi
}

last_incremental_success_start_time=0
last_full_success_start_time=0
last_success_start_time=0
incremental_backup=0
current_copy_exit_code=1
current_backup_result=1
current_backup_skipped=0

apt update 2> >(grep -v 'apt does not have a stable CLI interface' | error "apt update: ") > >(debug "apt update: ")
apt install -y rclone docker.io pv jq 2> >(grep -v "since apt-utils is not installed" |grep -v 'apt does not have a stable CLI interface' | error "apt install: ") > >(debug "apt install: ")

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

echo "last_full_success_start_time: $last_full_success_start_time" | debug
echo "last_incremental_success_start_time: $last_incremental_success_start_time" | debug
echo "last_success_start_time: $last_success_start_time" | debug
echo "last_success_age: $last_success_age" | debug
date +%s > /etc/gitlab-backups/current_start_time
if [ -f /etc/gitlab-backups/file_list_before ]; then
  cat /etc/gitlab-backups/file_list_before | sort | uniq | grep -v '^$' > /tmp/file_list_before
  cat /tmp/file_list_before >/etc/gitlab-backups/file_list_before
  cat /etc/gitlab-backups/file_list_before | debug "file_list_before: "
fi

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

if [ $last_success_age -gt 3600 ]; then
  if [ $last_full_age -lt 2419200 ]; then
    previous_backup=$(find "${GITLAB_BACKUPS_DIR}" -maxdepth 1 -mindepth 1 -name "*.tar" | grep "${last_success_start_time}" | tail -1)
    previous_backup=$(basename "${previous_backup}" | awk 'BEGIN{FS="_gitlab"}{print $1}')
    info "Starting a GitLab Incremental Backup.  PREVIOUS_BACKUP=${previous_backup}"
    docker exec "${OMNIBUS_CONTAINER_NAME}" gitlab-backup create SKIP=${OMNIBUS_SKIP_OBJECTS} INCREMENTAL=yes PREVIOUS_BACKUP=${previous_backup}2> >(error "docker exec: gitlab-backup create: ") > >(debug "docker exec: gitlab-backup create: "); echo $? >/etc/gitlab-backups/current_exit_code;
    current_backup_result=$(cat /etc/gitlab-backups/current_exit_code)
    if [ $current_backup_result -ne 0 ]; then
      info "Starting a GitLab Full Backup due to incremental backup failure."
      docker exec "${OMNIBUS_CONTAINER_NAME}" gitlab-backup create SKIP=${OMNIBUS_SKIP_OBJECTS} 2> >(error "docker exec: gitlab-backup create: ") > >(debug "docker exec: gitlab-backup create: "); echo $? >/etc/gitlab-backups/current_exit_code;  
    else
      incremental_backup=1
    fi
  else
    info "Starting a GitLab Full Backup."
    docker exec "${OMNIBUS_CONTAINER_NAME}" gitlab-backup create SKIP=${OMNIBUS_SKIP_OBJECTS} 2> >(error "docker exec: gitlab-backup create: ") > >(debug "docker exec: gitlab-backup create: "); echo $? >/etc/gitlab-backups/current_exit_code;
  fi
  current_backup_result=$(cat /etc/gitlab-backups/current_exit_code)
else
  printf '%b\n' "Most recent successful backup was only $last_success_age seconds ago." | info
  current_backup_skipped=1
fi

# TODO: We also need the secrets files gitlab.rb and gitlab-secrets.json
docker exec "${OMNIBUS_CONTAINER_NAME}" cat /etc/gitlab/gitlab.rb >"${GITLAB_BACKUPS_DIR}/gitlab.rb" 2> >(error "docker exec: ") > >(debug "docker exec: ")
docker exec "${OMNIBUS_CONTAINER_NAME}" cat /etc/gitlab/gitlab-secrets.json >"${GITLAB_BACKUPS_DIR}/gitlab-secrets.json" 2> >(error "docker exec: ") > >(debug "docker exec: ")

find "${GITLAB_BACKUPS_DIR}" -maxdepth 1 -mindepth 1 -name "*.tar" | sort | uniq | grep -v '^$' > /tmp/file_list_after
if [ -f /tmp/file_list_after ]; then
  cat /tmp/file_list_after | debug "file_list_after: "
fi
diff -ruN /etc/gitlab-backups/file_list_before /tmp/file_list_after | grep -v '^\+++' | grep '^\+' | debug "diff: "
IFS=$'\n' read -d '' -r -a new_files < <(diff -ruN /etc/gitlab-backups/file_list_before /tmp/file_list_after | grep -v '^\+++' | grep '^\+')

current_start_time=0
for file in "${new_files[@]}"; do
  current_copy_exit_code=0
  abs_file=$(printf '%s' "${file}" | sed 's/^\+//g')
  rel_file=$(basename "${abs_file}")
  if [ ! "" == "${abs_file}" ]; then
    echo "New file was created: ${abs_file}" | verbose
    tar --append -f "${abs_file}" "${GITLAB_BACKUPS_DIR}/gitlab.rb" 2> >(grep -v "Removing leading" | error "tar: ") > >(debug "tar: ")
    tar --append -f "${abs_file}" "${GITLAB_BACKUPS_DIR}/gitlab-secrets.json" 2> >(grep -v "Removing leading" | error "tar: ") > >(debug "tar: ")
    #tar --list -f "${abs_file}" 2> >(error "tar: ") > >(debug "tar: ")
    # TODO: tweak chunk size based on backup file size
    debug "pv \"${abs_file}\" | openssl enc -aes-256-cbc -md sha512 -iter 8192000 -pass [MASKED] | rclone --config /tmp/rclone.conf rcat \"wasabi:${S3_BUCKET}/${rel_file}\""
    pv "${abs_file}" 2> >(error "pv: ") | openssl enc -aes-256-cbc -md sha512 -iter 8192000 -pass "${OPENSSL_PASS}" 2> >(error "openssl: ") | rclone --config /tmp/rclone.conf rcat "wasabi:${S3_BUCKET}/${rel_file}" 2> >(error "rclone: ") > >(debug "rclone: ")

    current_copy_exit_code=$(( ${PIPESTATUS[0]:-0} + ${PIPESTATUS[1]:-0} + ${PIPESTATUS[2]:-0} ))
    if [ $current_copy_exit_code -eq 0 ]; then
      printf '\n%s\n' "${abs_file}" >>/etc/gitlab-backups/file_list_before
    fi

    # TODO: check the size of the object in cloud storage matches the local size

    this_start_time=$(printf '%b' "${rel_file}" | awk 'BEGIN{FS="_"}{print $1}')
    if [ $this_start_time -gt $current_start_time ]; then
      current_start_time=$this_start_time
    fi
  fi
done

if [ $current_backup_result -eq 0 ]; then
  if [ $incremental_backup -gt 0 ] && [ $current_backup_result -eq 0 ]; then
    printf '%b' "${current_start_time}" > /etc/gitlab-backups/last_incremental_success_start_time
  elif [ $current_backup_result -eq 0 ]; then
    printf '%b' "${current_start_time}" > /etc/gitlab-backups/last_full_success_start_time
  fi
fi

if [ $current_backup_result -eq 0 ] || [ $current_backup_skipped -eq 1 ]; then
  # TODO: cleanup local files

  # cleanup remote files that are too old
  # TODO: Only count remote files that match our file naming pattern
  # TODO: Only count remote files that have a valid looking size
  all_remote_objects=$(rclone --config /tmp/rclone.conf lsjson "wasabi:${S3_BUCKET}/")
  printf '%s' "${all_remote_objects}" | jq -C | debug "all_remote_objects: "
  all_remote_objects_count=$(printf '%s' "${all_remote_objects}" | jq "length")
  if [ "${all_remote_objects_count}" -gt "${MINIMUM_COUNT_OF_BACKUPS_TO_KEEP:-14}" ]; then
    echo "More than ${MINIMUM_COUNT_OF_BACKUPS_TO_KEEP} backups exist in the remote repository.  Looking for candidates to prune." | info
    for (( i=0; i<$all_remote_objects_count; i++ )) do
      object_name=$(printf '%s' "${all_remote_objects}" | jq -r ".[$i].Name")
      object_date=$(printf '%s' "${object_name}" | awk 'BEGIN{FS="_"}{print $1}')
      all_remote_objects=$(printf '%s' "${all_remote_objects}" | jq ".[$i].UnixTime = ${object_date}")
    done

    old_objects=$(printf '%s' "${all_remote_objects}" | jq "[ .[] | select((.UnixTime | tonumber) < $minimum_timestamp_of_backup) ]")
    old_objects_count=$(printf '%s' "${old_objects}" | jq "length")
    for (( i=0; i<$old_objects_count; i++ )) do
      object_name=$(printf '%s' "${old_objects}" | jq -r ".[$i].Name")
      object_path=$(printf '%s' "${old_objects}" | jq -r ".[$i].Path")
      object_date=$(printf '%s' "${old_objects}" | jq -r ".[$i].UnixTime")
      echo "Backup '${object_name}', created $(date -d "@${object_date}") is more than ${MINIMUM_AGE_OF_BACKUP_TO_DELETE} seconds old.  It can be pruned." | info
      echo "rclone rm \"wasabi:${S3_BUCKET}/${object_path}\"" | debug
    done
  fi
elif [ $current_backup_skipped -lt 1 ]; then
  echo "Backup or upload process failed." | error
  sleep 1200
fi

if [ -f /etc/gitlab-backups/file_list_before ]; then
  cat /etc/gitlab-backups/file_list_before | sort | uniq | grep -v '^$' > /tmp/file_list_before
  cat /tmp/file_list_before >/etc/gitlab-backups/file_list_before
  cat /etc/gitlab-backups/file_list_before | debug "file_list_before: "
fi