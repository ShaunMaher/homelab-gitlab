#!/bin/bash

# Configuration for GitLabInstance2
GITLAB_TOKEN_2="your_gitlab_token_for_instance2"
GITLAB_INSTANCE_2="https://gitlabinstance2.com"

# Function to import group into GitLabInstance2
import_group() {
    local file_path=$1
    curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN_2" --form "file=@$file_path" "$GITLAB_INSTANCE_2/api/v4/groups/import"
}

# Import Groups
echo "Importing groups into GitLabInstance2..."
for file in group_*.tar.gz; do
    if [ -f "$file" ]; then
        echo "Importing group from file: $file"
        import_group "$file"
    fi
done

# Function to import project into GitLabInstance2
import_project() {
    local project_name=$1
    local file_path=$2
    curl --request POST --header "PRIVATE-TOKEN: $GITLAB_TOKEN_2" --form "path=$project_name" --form "file=@$file_path" "$GITLAB_INSTANCE_2/api/v4/projects/import"
}

echo "Group import completed."

# Import Projects
echo "Importing projects into GitLabInstance2..."
for file in project_*.tar.gz; do
    if [ -f "$file" ]; then
        echo "Importing project from file: $file"
        import_project "$file"
    fi
done

echo "Project import completed."
