# StorPool backups tab for FireEdge

**Optional, early proof of concept.** `install.sh` does not install it, it has
its own installer, and it may change or be dropped in a later release.

OpenNebula records the size of a backup once, when the backup finishes (see
[Backup size reporting](backup_size_reporting.md)). The tab adds a *StorPool*
entry to the Sunstone sidebar. It lists the VMs the user can see and, for
each VM, the backup images in a [StorPool backup datastore](backup_datastore.md)
and their restore points. Each restore point shows the size OpenNebula
recorded next to the current StorPool figures of its snapshots, read from
the `monitor_helper-sync` cache.

## Components

* `backup_space.py serve`: a Python 3 service, run by the systemd unit
  `backup-space.service` as `oneadmin`, listening on `127.0.0.1:2874`.
* `/etc/nginx/snippets/storpool-backup.conf`: proxies `/storpool/remoteEntry.js`
  and `/storpool/api/` to the service. It is included in the nginx server
  block that publishes FireEdge.
* The Sunstone tab and view files (`/etc/one/fireedge/sunstone/tabs/storpool-tab.yaml`
  and `views/{admin,groupadmin,user,cloud}/storpool-tab.yaml`) and a
  `StorpoolModule` entry in `/etc/one/fireedge/sunstone/remotes-config.yaml`.

The service checks the browser's FireEdge session cookie with
`/var/lib/one/.one/fireedge_key` and calls oned as that user, so a user sees
only the VMs and backups they could see in Sunstone. It listens on the
loopback interface only; publish it only through the nginx snippet.

## Install

Requirements: FireEdge published through nginx, with the server block in
`/etc/nginx/conf.d/frontend.conf` (`proxy_pass http://fireedge;`), and the
addon installed with `install.sh`.

From the addon source tree, as root on the front-end:

```
bash misc/backup-space/install-on-frontend.sh
```

The script copies the service to `/var/lib/one/remotes/misc/backup-space/`,
installs and starts the systemd unit, adds the nginx snippet and its include,
and reloads nginx. It registers the Sunstone module only after
`/storpool/remoteEntry.js` answers through nginx, because a module that fails
to load stops Sunstone. Reload Sunstone in the browser afterwards.

`NGINX_CONF` and `SUNSTONE` override the nginx file and the Sunstone
configuration directory. `install.sh` does not update the installed copy;
run the script again after an addon upgrade.

The service reads these environment variables (set them in the unit):
`SP_BACKUP_SPACE_CACHE` (the `monitor_helper-sync` cache directory),
`SP_BACKUP_SPACE_ONE_URL` (oned XML-RPC), `SP_BACKUP_SPACE_BIND`,
`SP_BACKUP_SPACE_PORT` and `SP_BACKUP_SPACE_KEY` (the FireEdge key file).

As `oneadmin`, `python3 /var/lib/one/remotes/misc/backup-space/backup_space.py vm <id>`
and `... vms` print the same data as JSON, authenticated with `one_auth`.

## Remove

1. Delete the `StorpoolModule` entry from
   `/etc/one/fireedge/sunstone/remotes-config.yaml` first, then the
   `storpool-tab.yaml` tab and view files.
2. Delete the `include snippets/storpool-backup.conf;` line from the nginx
   configuration, delete the snippet and reload nginx.
3. `systemctl disable --now backup-space.service`, delete the unit file and
   `/var/lib/one/remotes/misc/backup-space/`.
