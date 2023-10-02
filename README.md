# Gitlab Omnibus with Runner, Cloudflared Tunnel Ingress and Cloud Backups
## TODOs
* Add health checks to containers
* Make the pages tunnel depend on Omnibus being healthy so it doesn't start
  before pages are actually accessible.  This will allow the alternative pages
  server to continue receiving 100% of requests until the local node is
  actaully ready.
  
## Cloudflare tunnels
We will establish two tunnels to Cloudflare.  One will be for Gitlab Pages
traffic and the other will be for all other traffic.  This will allow us to 
seperate the Gitlab Pages requests and handle them differently.
```
cloudflared tunnel create pages.ghanima.net
```

```
cloudflared tunnel create git.ghanima.net
```

## S3
We will be storing Gitlab Pages and Gitlab backups in S3 storage.  For this
implementation we will specifically use Wasabi because it's cheap and seems
reliable.

### Buckets
Create two buckets (maybe more later):
* `pages.git.ghanima.net`
* `backups.git.ghanima.net`

### Users
Create two users:
* git.ghanima.net
* pages.ghanima.net

Each new user will have an "ARN".  This ARN will be used in the Access Policies.

### Access policies
The [pages.git.ghanima.net Bucket's Access Policy](arn:aws:s3:::pages.git.ghanima.net.json)
allows the "git.ghanima.net" user read-write access to the bucket contents but
allows the "pages.ghanima.net" user read-only access.

* Replace instances (2) of `"AWS": "arn:aws:iam::100000190796:user/git.ghanima.net"`
with the ARN of the "git.ghanima.net" user.
* Replace instances (2) of `"AWS": "arn:aws:iam::100000190796:user/pages.ghanima.net"`
  with the ARN of the "pages.ghanima.net" user.
* Replace instances of `"Resource": "arn:aws:s3:::pages.git.ghanima.net/*"` (1)
  and `"Resource": "arn:aws:s3:::pages.git.ghanima.net"` (1) with the ARN of
  the backups.git.ghanima.net bucket.

The [backups.git.ghanima.net Bucket's Access Policy](arn:aws:s3:::backups.git.ghanima.net.json)
allows the "git.ghanima.net" user read-write access to the bucket.

* Replace instances of `"AWS": "arn:aws:iam::100000190796:user/git.ghanima.net"`
with the ARN of the "git.ghanima.net" user.
* Replace instances of `"Resource": "arn:aws:s3:::backups.git.ghanima.net/*"` and
  `"Resource": "arn:aws:s3:::backups.git.ghanima.net"` with the ARN of the
  backups.git.ghanima.net bucket.

## Environment variables
The following environment variables must be created:
* For S3 Object storage
  * `S3_ACCESS_KEY`: Access Key ID for the "git.ghanima.net" user.  Used for Gitlab Pages access to the S3 storage.
  * `S3_SECRET_KEY`: Access Key Secret for the "git.ghanima.net" user.  Used for Gitlab Pages access to the S3 storage.
  * `S3_PAGES_BUCKET`: The S3 bucket that pages content will be stored in
  * `S3_REGION`: For Wasabi, this should always be `us-east-1`
  * `S3_ENDPOINT`: For Wasabi, see [this list](https://docs.wasabi.com/docs/what-are-the-service-urls-for-wasabis-different-storage-regions)
  * `CF_PAGES_TUNNEL_UUID`: 
  * `CF_PAGES_CREDENTIALS`: 
  * `CF_TUNNEL_UUID`: 
  * `CF_CREDENTIALS`: 
  * `BACKUPSRUNNER_REGISTRATION_TOKEN`: Create but leave blank initially.

## Post Installation
### Disable "Sign-up"
* **Admin Area** -> **General** -> **Sign-up Restrictions** -> uncheck **Sign-up enabled**

### Create a new user

### Local DNS Override (so the runner isn't going via Cloudflare)
TODO: This would be better implemented as a link:
```yaml
links:
  - omnibus:git.ghanima.net
```

### Register the runner
TODO: Update the docker-compose.yml file to automatically register the runner
like what we have for the backuprunner.

### SSO with Google Workspace
TODO

### Cloudflare Access
#### SSH Access

## Backup Configuration
**Reference:** https://docs.gitlab.com/ee/raketasks/backup_gitlab.html

The script `backup.sh` does the following:
* Requests GitLab produce a Full or Incremental backup.  Full backups are
  produced if:
  * No local incremental backups exist
  * It has been more than 4 weeks since the last Full backup.
* Appends the `gitlab.rb` and `gitlab-secrets.json` files to the backup
  * Generally these files should be considered "sensitive" but the backup file
    is encrypted before it is sent to Cloud Storage so if this file is leaked
    the attacker still can't access these sensitive files without first
    breaking the encryption
* Encrypts and streams the backup to S3 Cloud Storage with the `rclone` tool
  * I use Wasabi for cost effective S3 cloud storage (and I'm not paid to say
    that, unfortunately)

### Configuration
* Create a project for GitLab backups.  It can be this same project.
* Create a project owned runner
  * TODO
* Add/update the `BACKUPSRUNNER_REGISTRATION_TOKEN` stack environment variable
  to the value created in the previous steps.
* Disable shared runners for this project
* Add the following environment variables to *Settings* -> *CI/CD* -> *Variables*:
  * `S3_ACCESS_KEY`
  * `S3_SECRET_KEY`
  * `S3_REGION`: For Wasabi, this should always be `us-east-1`
  * `S3_ENDPOINT`: For Wasabi, see [this list](https://docs.wasabi.com/docs/what-are-the-service-urls-for-wasabis-different-storage-regions)
  * `BACKUP_ENCRYPTION_PASSWORD`: 
  * `S3_BUCKET`: The name of the target bucket to store the backups
  * `OMNIBUS_SKIP_OBJECTS` (optional): You can skip backing up large objects
    that can be easily recreated if they are lost.  For example "`registry,artifacts,packages`"
* Create a scheduled pipeline to run the backups.

## Storing Gitlab Pages (and other selected objects) in Cloud Object Storage
**Reference:** https://docs.gitlab.com/ee/administration/pages/#using-object-storage

The following will store certain objects in Wasabi cloud storage.  The initial
goal is to have pages hosted in the cloud but to do this you need a seperate
GitLab instance pointing at the same Object Storage as the primary instance.

TODO: more info

## Work in Progress: Pages server on a VPS (for availability and to reduce dependence on home internet connection)
**Reference:** https://docs.gitlab.com/ee/administration/pages/#running-gitlab-pages-on-a-separate-server

Should we run a wireguard tunnel between servers or just traverse the internet?

On the Pages server
```ruby
roles ['pages_role']
pages_external_url "http://<pages_server_URL>"
gitlab_pages['gitlab_server'] = 'https://git.ghanima.net'
```

On the local gitlab server.

TODO: Do we disable pages locally or use it as a secondary server?  Both
servers have a CF tunnel up and... CF free doesn't have load balancing I don't
think.

```ruby
pages_external_url "http://<pages_server_URL>"
gitlab_pages['enable'] = false
pages_nginx['enable'] = false
```