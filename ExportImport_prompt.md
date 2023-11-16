```
Can you please write a bash script that meets the following OBJECTIVES

OBJECTIVES
* Uses the GitLab API to enumerate all projects in GitlabInstance1
* Uses the GitLab API to export each project into an archive
  * This MUST be all the project elements available for export from the API.  NOT just the repository.
* Uses the Gitlab API of a second GitLab instance (GitLabInstance2) to import each previously exported project
* Maintains the project group hierarchy from GitlabInstance1 into GitLabInstance2
* Include basic error handling
* GitLab import and export API information can be found here: https://docs.gitlab.com/ee/api/project_import_export.html
* Abort is any step fails
```
