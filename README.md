# Gitlab Omnibus with Shared Runner, Cloudflared Tunnel Ingress, Separate Pages Instance and Cloud Backups
This project documents the process I used to create a self-hosted GitLab
instance in my homelab.

The homelab components are all inside a Ubuntu VM with Docker and Portainer
installed.  Watchtower is used to keep the various OCI images up-to-date.
TODO: Add the watchtower details here or link to it's separate project.

The whole Ubuntu VM is backed up locally and to a cloud VPS.  TODO: Link to the
sanoid-pull-backups project here.

Goals:
* No firewall requirements for the homelab network.  No port forwards, no need
  to manage firewall whitelists, DDoS protection, etc.
* Good availablity but an outage of few minutes a week is acceptable in
  exchange for automated update processes to restart/reboot things.
* Get the most out of Cloudflare's generous Free offerings.
  * My domain's DNS is already hosted by Cloudflare
* GitLab Pages are to be hosted by both the local GitLab instance (in the
  homelab) and a VPS.  I don't want my Pages to rely on my home infrastructure
  (residential grade internet connection, oldish server, no UPS, automatic
  updates and reboots, etc.).
* GitLab must be backed up offsite to cost effective storage.
  * I'm only backing up a subset of GitLab data.  To reduce the size of the
    data that must be uploaded to the cloud (over my home internet connection)
    I do NOT backup objects that can be easily recreated (packages, OCI images,
    CI/CD artifacts).  These can be recreated by simply re-running the CI/CD
    pipelines that created them.
* The Ubuntu VM has 2 separate virtual disks.  One is dedicated for
  "BulkStorage".  In my case the "BulkStorage" disk is on mechanical hard
  drives and the other virtual disk is on SSD.  Only the virtual disk on SSD
  is backed up to the cloud and I need to minimise the changes that are written
  to this disk to minimise the data that needs to be sent.  For this reason,
  any GitLab data that frequently changes, but is of little value, is mapped to
  the "BulkStorage" volume.
* Minimal manual maintenance.
  * The Ubuntu VM in the homelab is configured with unattended upgrades with
    automatic reboots.
  * The Ubuntu VPS is also configured with unattended upgrades with automatic
    reboots.
  * Watchtower is used to keep the OCI images up-to-date

Major components:
* docker-compose.yml - Deployed by Portainer on the homelab Ubuntu VM:
  * A GitLab Onmibus container
  * A GitLab Runner container for running CI/CD jobs as a shared runner
  * A second GitLab runner for running backups of GitLab itself
    * This runner has additional permissions and access to the Gitlab Omnibus
      container, that the shared runner doesn't have.
  * 2x Cloudflared tunnel containers
  * 2x containers that automatically generate configuration for the cloudflared
    containers
* docker-compose-pages.yml - Deployed by Portainer on the Ubuntu VPS:
  * A GitLab Omnibus container that has only the "pages" role (i.e. only hosts
    "GitLab Pages" and nothing else).
  * A cloudflared tunnel container.
  * A container that automatically generates configuration for the cloudflared
    container.
* backup.sh: A script to send GitLab backups to offsite cloud storage

## TODOs
* Add health checks to containers

## Deployment Process
### Create cloudflared tunnels
We will establish two tunnels to Cloudflare.  One will be for Gitlab Pages
traffic and the other will be for all other traffic.  This will allow us to 
seperate the Gitlab Pages requests and handle them differently.

The following commands will, after asking you to authenticate with Cloudflare,
create some tunnels and credentials that allows the cloudflare instances that
will be deployed to connect to the Cloudflare network.

Create a tunnel specifically for GitLab Pages.  This tunnel will be used by
both the homelab Omnibus instance and the VPS Pages only Omnibus instance so
that cloudflare will route traffic to whichever one is up, without needing a
cloud load balancer.
```
cloudflared tunnel create pages.ghanima.net
```

Create a tunnel for all remaining GitLab services.
```
cloudflared tunnel create git.ghanima.net
```

### S3 Object Storage (for Pages and Backups)
In order for GitLab Pages to be hosted by separate GitLab instances, the Pages
artifacts must be stored in a manner that both instances can access.

We also need a place to store the GitLab backups.

I chose to store them in Wasabi's object storage (unfortnately, not a paid
endoursement), which presents an S3 compatible API, because I started this
project before Cloudflare started offering it's R2 storage on the Free plan.

I need less then 1TiB of cloud storage so I'm happy to pay a few dollars a
month and know it's not going to disappear if someone decides they were being
too generous.

#### Buckets
Create two buckets (maybe more later):
* `pages.git.ghanima.net`
* `backups.git.ghanima.net`

#### Users
Create two users:
* git.ghanima.net
* pages.ghanima.net

Each new user will have an "ARN".  This ARN will be used in the Access Policies.

#### Access policies
The [pages.git.ghanima.net Bucket's Access Policy](arn-aws-s3---pages.git.ghanima.net.json)
allows the "git.ghanima.net" user read-write access to the bucket contents but
allows the "pages.ghanima.net" user read-only access.

* Replace instances (2) of `"AWS": "arn:aws:iam::100000190796:user/git.ghanima.net"`
with the ARN of the "git.ghanima.net" user.
* Replace instances (2) of `"AWS": "arn:aws:iam::100000190796:user/pages.ghanima.net"`
  with the ARN of the "pages.ghanima.net" user.
* Replace instances of `"Resource": "arn:aws:s3:::pages.git.ghanima.net/*"` (1)
  and `"Resource": "arn:aws:s3:::pages.git.ghanima.net"` (1) with the ARN of
  the backups.git.ghanima.net bucket.

The [backups.git.ghanima.net Bucket's Access Policy](arn-aws-s3---backups.git.ghanima.net.json)
allows the "git.ghanima.net" user read-write access to the bucket.

* Replace instances of `"AWS": "arn:aws:iam::100000190796:user/git.ghanima.net"`
with the ARN of the "git.ghanima.net" user.
* Replace instances of `"Resource": "arn:aws:s3:::backups.git.ghanima.net/*"` and
  `"Resource": "arn:aws:s3:::backups.git.ghanima.net"` with the ARN of the
  backups.git.ghanima.net bucket.

### Portainer Stack(s)
#### TODO: How to deploy the stacks
TODO

#### Environment variables
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

### Public DNS Records in Cloudflare
TODO

## Post Deployment
Some additional manual steps to tweak the new GitLab instance

### Disable "Sign-up"
* **Admin Area** -> **General** -> **Sign-up Restrictions** -> uncheck **Sign-up enabled**

### Create a new user

### Local DNS Override (so the runner isn't going via Cloudflare)
TODO: This would be better implemented as a link:
```yaml
links:
  - omnibus:git.ghanima.net
```

### Register the shared runner
TODO: Update the docker-compose.yml file to automatically register the runner
like what we have for the backuprunner.

### SSO with Google Workspace
TODO

### cloudflared Access
It is possible to restrict access to, for example, the SSH service, to only
connections from clients that are also using cloudflared.

#### SSH Access
TODO: Do we want external SSH access at all.  HTTPS is already available.

### Backup Configuration
**Reference:** https://docs.gitlab.com/ee/raketasks/backup_gitlab.html

The script `backup.sh` does the following:
* Requests GitLab produce a Full or Incremental backup.  Full backups are
  produced if:
  * No local incremental backups exist
  * It has been more than 4 weeks since the last Full backup.
  * TODO: The full incremental backups aren't really that much smaller than the
    full backups (since we skip backing up some objects).  Maybe we don't do
    incremental backups at all.
* Appends the `gitlab.rb` and `gitlab-secrets.json` files to the backup
  * Generally these files should be considered "sensitive" but the backup file
    is encrypted before it is sent to Cloud Storage so if this file is leaked
    the attacker still can't access these sensitive files without first
    breaking the encryption
* Encrypts and streams the backup to S3 Cloud Storage with the `rclone` tool

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

> This section needs to be rewritten and moved to the Portainer Stack(s) section

The following will store certain objects in Wasabi cloud storage.  The initial
goal is to have pages hosted in the cloud but to do this you need a seperate
GitLab instance pointing at the same Object Storage as the primary instance.

TODO: more info

## Work in Progress: Pages server on a VPS (for availability and to reduce dependence on home internet connection)
**Reference:** https://docs.gitlab.com/ee/administration/pages/#running-gitlab-pages-on-a-separate-server

> This section needs to be rewritten and moved to the Portainer Stack(s) section

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