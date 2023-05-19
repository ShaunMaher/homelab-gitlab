# Gitlab Omnibus with Runner and Cloudflared Tunnel Ingress
## Post Installation
### Disable "Sign-up"
* **Admin Area** -> **General** -> **Sign-up Restrictions** -> uncheck **Sign-up enabled**

### Create a new user

### Local DNS Override (so the runner isn't going via Cloudflare)

### Register the runner

### Cloudflare Access

#### SSH Access

## Work in Progress: Backup Configuration
TODO:
* We need some non-COW storage (so that the underlying ZFS dataset doesn't get
  a bunch of changes that will cause the incremental backups to grow) to hold
  the .tar file that is created before it is uploaded to the Cloud.

```ruby
gitlab_rails['backup_upload_connection'] = {
  'provider' => 'AWS',
  'region' => 'eu-central-1',
  'aws_access_key_id' => 'AKIAKIAKI',
  'aws_secret_access_key' => 'secret123'
}
gitlab_rails['backup_upload_remote_directory'] = 'my.s3.bucket'
gitlab_rails['backup_multipart_chunk_size'] = 104857600

# We need some non-COW storage for
gitlab_rails['backup_path']
```

## Work in Progress: Storing some objects in Cloud Object Storage
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