#!/bin/bash

# Configuration for GitLabInstance1
GITLAB_TOKEN_1="your_gitlab_token_for_instance1"
GITLAB_INSTANCE_1="https://gitlabinstance1.com"

# Function definitions for groups (enumerate_groups, export_group, check_group_export_status, download_group_export) remain the same

# Function to enumerate all projects in GitLabInstance1
enumerate_projects() {
    curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN_1" "$GITLAB_INSTANCE_1/api/v4/projects"
}

# Function to export a project
export_project() {
    local project_id=$1
    curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN_1" "$GITLAB_INSTANCE_1/api/v4/projects/$project_id/export"
}

# Function to check project export status
check_project_export_status() {
    local project_id=$1
    curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN_1" "$GITLAB_INSTANCE_1/api/v4/projects/$project_id/export" | jq -r '.export_status'
}

# Function to download project export
download_project_export() {
    local project_id=$1
    curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN_1" "$GITLAB_INSTANCE_1/api/v4/projects/$project_id/export/download" --output "project_${project_id}.tar.gz"
}

# Function to enumerate all groups in GitLabInstance1
enumerate_groups() {
    curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN_1" "$GITLAB_INSTANCE_1/api/v4/groups"
}

# Function to export a group
export_group() {
    local group_id=$1
    curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN_1" "$GITLAB_INSTANCE_1/api/v4/groups/$group_id/export"
}

# Function to check group export status
check_group_export_status() {
    local group_id=$1
    curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN_1" "$GITLAB_INSTANCE_1/api/v4/groups/$group_id/export" | jq -r '.export_status'
}

# Function to download group export
download_group_export() {
    local group_id=$1
    curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN_1" "$GITLAB_INSTANCE_1/api/v4/groups/$group_id/export/download" --output "group_${group_id}.tar.gz"
}


# Export Groups
echo "Enumerating groups from GitLabInstance1..."
groups=$(enumerate_groups)
if [ $? -ne 0 ]; then
    echo "Failed to enumerate groups"
    exit 1
fi

for group in $groups; do
    group_id=$(echo $group | jq -r '.id')

    echo "Exporting group: $group_id"
    export_group $group_id

    # Check group export status in a loop
    while true; do
        export_status=$(check_group_export_status $group_id)
        if [ "$export_status" == "finished" ]; then
            break
        elif [ "$export_status" == "failed" ]; then
            echo "Group export failed for group ID: $group_id"
            exit 1
        fi
        sleep 10
    done

    echo "Downloading group: $group_id"
    download_group_export $group_id
done

echo "Group export completed."

# Export Projects
echo "Enumerating projects from GitLabInstance1..."
projects=$(enumerate_projects)
if [ $? -ne 0 ]; then
    echo "Failed to enumerate projects"
    exit 1
fi

for project in $projects; do
    project_id=$(echo $project | jq -r '.id')

    echo "Exporting project: $project_id"
    export_project $project_id

    # Check project export status in a loop
    while true; do
        export_status=$(check_project_export_status $project_id)
        if [ "$export_status" == "finished" ]; then
            break
        elif [ "$export_status" == "failed" ]; then
            echo "Project export failed for project ID: $project_id"
            exit 1
        fi
        sleep 10
    done

    echo "Downloading project: $project_id"
    download_project_export $project_id
done

echo "Project export completed."
