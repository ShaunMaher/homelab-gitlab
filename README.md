# Gitlab Omnibus with Runner and Cloudflared Tunnel Ingress
## Environment variables
The following environment variables must be created:
* For S3 Object storage
  * `S3_ACCESS_KEY`
  * `S3_SECRET_KEY`
  * `S3_PAGES_BUCKET`: The S3 bucket that pages content will be stored in
  * `S3_REGION`: For Wasabi, this should always be `us-east-1`
  * `S3_ENDPOINT`: For Wasabi, see [this list](https://docs.wasabi.com/docs/what-are-the-service-urls-for-wasabis-different-storage-regions)
  * `BACKUPSRUNNER_REGISTRATION_TOKEN`: Create but leave blank initially.

## Post Installation
### Disable "Sign-up"
* **Admin Area** -> **General** -> **Sign-up Restrictions** -> uncheck **Sign-up enabled**

### Create a new user

### Local DNS Override (so the runner isn't going via Cloudflare)

### Register the runner
TODO: Update the docker-compose.yml file to automatically register the runner
like what we have for the backuprunner.

### Cloudflare Access

#### SSH Access

## Work in Progress: Backup Configuration
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

## Work in Progress: Storing some objects in Cloud Object Storage
**Reference:** https://docs.gitlab.com/ee/administration/pages/#using-object-storage

The following will store certain objects in Wasabi cloud storage.  The initial
goal is to have pages hosted in the cloud but to do this you need a seperate
GitLab instance pointing at the same Object Storage as the primary instance.

```ruby
gitlab_rails['object_store']['enabled'] = true
gitlab_rails['object_store']['proxy_download'] = true
gitlab_rails['object_store']['connection'] = {
  'provider' => 'AWS',
  'region' => 'eu-central-1',
  'aws_access_key_id' => '<AWS_ACCESS_KEY_ID>',
  'aws_secret_access_key' => '<AWS_SECRET_ACCESS_KEY>'
  'endpoint' -> 'https://s3.eu-central-1.wasabisys.com'
}
gitlab_rails['object_store']['objects']['artifacts']['bucket'] = 'artifacts.git.ghanima.net'
gitlab_rails['object_store']['objects']['lfs']['bucket'] = 'lfs.git.ghanima.net'
gitlab_rails['object_store']['objects']['uploads']['bucket'] = 'uploads.git.ghanima.net'
gitlab_rails['object_store']['objects']['packages']['bucket'] = 'packages.git.ghanima.net'
gitlab_rails['object_store']['objects']['pages']['bucket'] = 'pages.git.ghanima.net'
gitlab_rails['object_store']['objects']['dependency_proxy']['enabled'] = false
gitlab_rails['object_store']['objects']['terraform_state']['enabled'] = false
gitlab_rails['object_store']['objects']['ci_secure_files']['enabled'] = false
gitlab_rails['object_store']['objects']['external_diffs']['enabled'] = false
```

Bucket Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AddCannedAcl",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::100000190796:user/git.ghanima.net"
      },
      "Action": [
        "s3:GetObject",
        "s3:GetObjectAcl",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::pages.git.ghanima.net/*"
    },
    {
      "Sid": "AddCannedAcl",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::100000190796:user/git.ghanima.net"
      },
      "Action": [
        "s3:GetObject",
        "s3:GetObjectAcl",
        "s3:ListBucket",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::pages.git.ghanima.net"
    },
    {
      "Sid": "AddCannedAcl",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::100000190796:user/pages.ghanima.net"
      },
      "Action": [
        "s3:GetObject",
        "s3:GetObjectAcl",
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::pages.git.ghanima.net/*"
    },
    {
      "Sid": "AddCannedAcl",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::100000190796:user/pages.ghanima.net"
      },
      "Action": [
        "s3:GetObject",
        "s3:GetObjectAcl",
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::pages.git.ghanima.net"
    }
  ]
}
```

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