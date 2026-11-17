# Backup size reporting

How much the sizes OpenNebula shows for a backup in a StorPool backup datastore
can be trusted, and which everyday schedules keep them usable. The backup and
the restore do not read these numbers. A size of 0 or a size that is far from
the bytes on disk still leaves a restorable snapshot. What breaks is the
quota, the figure in `oneimage show` / Sunstone, and anyone adding up backup
images to see how full the cluster is. Interactive (OneBEX) backups do not use
this datastore; their size is described in
[Interactive backups](interactive_backup.md).

Two numbers exist and they answer different questions:

* the backup image `SIZE` (and each increment's `SIZE`), printed once by the
  datastore `backup` action and then kept;
* the datastore `USED_MB` / `TOTAL_MB` / `FREE_MB` from `monitor`, display
  only. The StorPool backup datastore requires `DATASTORE_CAPACITY_CHECK=NO`,
  so free space never accepts or refuses a backup.

`spaceUsed` and `storedSize` are client bytes. Replication is outside both
numbers, as it is for the image and system datastores.

## What OpenNebula does with the size

The datastore `backup` action reports one size per backup, in mebibytes.

* A `FULL` backup, or the first backup of a chain, becomes the image `SIZE`.
  A later `INCREMENT` keeps its own size and the image `SIZE` becomes the sum
  of the increments.
* The user and group quota of the backup datastore is charged with the
  reported size and released when the backup is deleted or flattened away.
* A flatten replaces the size of the increment that becomes the new base. No
  other operation writes a size again, so a wrong size stays for as long as
  that backup is kept.

Restores use the backup manifest and `vm.xml`. `KEEP_LAST` counts increments
or images. Neither looks at the size.

The optional proof-of-concept [FireEdge tab](backup_space.md) shows the
current StorPool figures of each backup next to the recorded size.

## The cache interval

`VolumesSpace` and `SnapshotsSpace` are cluster-wide, so the drivers read the
copies `monitor_helper-sync` keeps under `/var/cache/addon-storpool-monitor/`.
The helper's timer runs every 4 minutes (`AccuracySec=1min` on
`monitor_helper-sync.timer`). A call is refreshed only when its file is older
than the per-call setting, `SP_VOLUMESSPACE_SECONDS` or
`SP_SNAPSHOTSSPACE_SECONDS`. When that setting is absent the call uses
`SP_DEFAULT_SECONDS`. The shipped value in `monitor_helper-syncrc` is 1800.
Three `VolumesSpace` bodies are kept (the current file, `.1`, and `.2`).

The age that matters is that interval plus one helper period. Call it **A**:

* **Avol** — `SP_VOLUMESSPACE_SECONDS`, or `SP_DEFAULT_SECONDS`, plus about 5
  minutes. Image sizes use this. With the shipped value, **Avol** is about 35
  minutes.
* **Asnap** — `SP_SNAPSHOTSSPACE_SECONDS`, or `SP_DEFAULT_SECONDS`, plus about
  5 minutes. The datastore monitor and flatten use this. Same shipped age.

Lowering the variable shrinks the miss, down to the helper period. Below that
period the helper already refreshes on every run, and the cost is a
cluster-wide call every 4 minutes. Raising it is the change that moves a
schedule from usable to not feasible. Every judgement below is a comparison
of the backup interval **T** with **Avol** or **Asnap**, not with 1800 itself.
1800 only says where the shipped configuration sits.

`oned` polls `monitor` on its own `MONITORING_INTERVAL_DATASTORE` (often 300
s). `USED_MB` can be **Asnap** plus that interval behind the cluster. The
image `SIZE` is fixed at the backup and does not wait for that poll.

A disk on another cluster of the multi-cluster is read from that cluster's
cache file. The backup does not refresh a foreign cluster. The front-end
helper has to be writing that file.

## How each path gets its size

### Local full, and increment 0

The sum of `spaceUsed` of the disk volumes and the NVRAM volume: written
data, parents included (the image the disk was cloned from), unwritten space
left out. It misses the writes in the last **Avol**. A disk the cache does
not list is charged its virtual size until a refresh contains it. The service
volume (vm.xml, vTPM state, file NVRAM) is omitted.

This number is "how much data the VM holds," stale by **Avol**. The extra
blocks the snapshots occupy are what `USED_MB` sums.

### Later local increment

The snapshot just taken is newer than a cache that refreshes on **Asnap**, so
the exact `storedSize` of that snapshot is almost never what gets registered.
It is used only when a `SnapshotsSpace` refresh happens to land between the
snapshot and the `backup` action. For any **Asnap** much larger than that
action, that race does not happen.

Otherwise the size is the volume's `storedSize` from the newest `VolumesSpace`
body whose call started after the previous backup of this VM and ended before
this one. That is the data written since the previous snapshot, minus whatever
was written after that sample. When no such body exists the increment is
stored as 0.

Let **T** be the time since the previous backup:

* **T > Avol.** A sample is expected. The miss is at most the last **Avol** of
  writes. Spread evenly, the recorded size includes at least `(T − Avol) / T`
  of the interval.
* **T ≤ Avol.** The usual result is 0, or only the writes from a sample taken
  just after the previous backup. Backing up more often than **Avol** is what
  produces the zeros.

Bands, for writes spread through the interval:

| **Avol** compared with **T** | What you get |
|---|---|
| at most **T/12** | Sound. The miss is a small fraction of the interval (about an hour on a daily job). |
| **T/12** to **T/8** | Ok-ish. A visible undercount, still the right order of magnitude. |
| **T/8** up to **T** | Rough. A sample usually exists and can omit most of the interval. A write burst in the blind window can record as nothing. |
| **Avol ≥ T** | Not feasible. The increment is commonly 0, and that 0 is permanent. |

With the shipped **Avol** of about 35 minutes: a daily job is sound (**T/12**
is 2 hours), a 6-hour job is ok-ish, a 4-hour job is just into the rough
band, an hourly job is rough (the miss can be half the hour), and anything
at 35 minutes or faster is not feasible.

Cases that push a job down a band even when **T** and **Avol** look fine:

* The interval's writes sit in the last **Avol** before the backup. The miss
  is the whole burst.
* `monitor_helper-sync` is stopped, or `VolumesSpace` fails. The increment is 0.
* A disk is absent from the cache. That disk adds nothing. On a full backup
  the same disk adds its virtual size instead.
* Several backups force `VolumesSpace` refreshes in one go (a volume missing
  from the cache is what triggers one) and rotate the in-window body out.
  Three bodies absorb two refreshes. A third drops the sample and the
  increment is 0. A normal full backup does not refresh when the file is
  already present, so a mixed nightly run does not do this by itself.
* The helper has never seen that StorPool cluster, so the per-cluster file
  is missing.

### Flatten of a local chain

`KEEP_LAST` drops the oldest increments and StorPool merges their blocks into
the survivor. The new base is the first dropped increment's recorded SIZE,
minus that snapshot's `storedSize`, plus the merged `storedSize`. With one
increment dropped per backup and the snapshots present in `SnapshotsSpace`,
that is the merged content. Dropping several at once is an upper bound. When
the base is newer than the cache, the base keeps the sum of the recorded
sizes, so a 0 or a low estimate from earlier is what the quota keeps.

Snapshots from a daily chain are many **Asnap** old, so a helper that has
been running serves the flatten. The fallback hits when **Asnap** is longer
than the age of the base, or the helper has been down.

### Remote mode

Every backup, increment or not, is the full logical content, stale by
**Avol**. The source cluster does not keep the previous snapshot, so the
delta that landed on the target is not measurable here. Shortening
`SP_DEFAULT_SECONDS` makes that full-content figure fresher. It does not turn
it into a delta.

OpenNebula sums increment sizes. Each one is about a full copy, so the image
grows by about one logical size per backup. `KEEP_LAST` stops the growth at
about `KEEP_LAST` full copies: the flatten sets the new base to that base's
own recorded size, which is already a full copy, and every newer increment
still carries a full copy. The steady quota is about `KEEP_LAST` times the
VM, for a chain whose target holds one copy plus the deltas.

`USED_MB` on a target that is a cluster of this multi-cluster is the
`storedSize` of the copies, late by **Asnap**. A target that is only a
location name reports zeros, at any cache interval.

### Datastore monitor

`USED_MB` sums `storedSize` of this OpenNebula instance's backup snapshots on
the local cluster, or of the copies when `SP_BACKUP_LOCATION` names a cluster.
Two backup datastores on the same cluster each show the combined total.
`TOTAL_MB` and `FREE_MB` are the pool of the backup datastore's template
(`SP_DEFAULT_TEMPLATE`, else the cluster default; on a cluster target, that
cluster's backup template). Snapshots stay on the volume's own template. The
pool figures match the snapshots when those templates share a placement
group, and they describe a different pool when they do not.

Deleting a parent outside the chain (the image the disk was cloned from, an
older chain) merges those blocks into the oldest kept backup. `USED_MB`
follows on the next refresh. The image `SIZE` does not, because OpenNebula
will not resize it. Over a long life the quota drifts low relative to the
blocks that snapshot then holds.

## Practical schemes

Live or poweroff, and `FS_FREEZE`, do not change the size. `INCREMENT_MODE`
(`CBT` or `SNAPSHOT`) has no meaning for StorPool disks. The parameters that
do are `MODE`, the schedule (**T**), `KEEP_LAST`, local or
`SP_BACKUP_LOCATION`, and **Avol** / **Asnap**.

Quota below means the user and group backup-datastore quota. Sites that do
not set one still see the same numbers in Sunstone. A 0 there looks like a
failed backup and is only an accounting 0.

### Daily full, keep a week

The usual OpenNebula backup job. `MODE=FULL`, once a day, `KEEP_LAST=7`,
local StorPool datastore.

Each image is the VM's logical content, short by the last **Avol** of writes.
The quota settles near 7 times that. `USED_MB` is the unique blocks of the
seven snapshots and is smaller whenever the VMs share a parent image or
change slowly. The two will not add up. That is the number working, and it
is the question operators ask first.

Ok-ish with the shipped cache, and it stays ok-ish while the bytes written
during **Avol** are an acceptable error on the VM's logical size. A quiet VM
stays close even with a long interval. It stops being a fair bill when
**Avol** covers a large part of the VM's write history (a cache interval of
days), or when disks stay on their virtual size because the helper has not
listed them yet. `KEEP_LAST` does not fix the per-image error. It only caps
how many full logical sizes the quota holds. Leaving `KEEP_LAST` unset makes
the quota grow by one logical size per day for the life of the VM.

`KEEP_LAST` of 14 or 30 is the same quality per image. The quota scales with
the count. The gap between that quota and `USED_MB` gets wider. Weekly full
with `KEEP_LAST=4` has the same per-image error: still the last **Avol** of
writes on the VM's logical content. The longer gap between backups does not
shrink that error.

### Daily incremental, keep a week or two

`MODE=INCREMENT`, once a day, `KEEP_LAST=7` or 14, local.

The first backup is the logical content, same as a full. Each later day is a
delta. With the shipped **Avol** of about 35 minutes, a daily **T** puts
**Avol** well under **T/12** (2 hours), so the miss is about 35 minutes of a
day of even writes. After the chain fills,
each new backup drops the oldest increment, the flatten folds it into the
base, and the image size stays on the order of the VM's logical content plus
the deltas still in the chain.

This is the incremental scheme that is worth using for quotas, with the
shipped cache or any **Avol** up to about 2 hours (**T/12**). Up to about 3
hours (**T/8**) it is still ok-ish. From there to just under 24 hours it is
rough. At **Avol** of 24 hours or more the daily increment is commonly 0 and
the scheme is not feasible for accounting. A helper that is down makes every
later increment 0 whatever the setting is. A flatten during that outage, or
while **Asnap** is still longer than the age of the base, keeps those
recorded zeros.

Without `KEEP_LAST` the image size adds every day's delta forever, including
rewrites of the same blocks, so a VM that rewrites 10 GB a day grows its
backup quota by 10 GB a day even though the VM does not grow. `KEEP_LAST` is
what keeps this scheme bounded.

### Incremental every 4 to 6 hours

Same `MODE=INCREMENT` and a local datastore, with a backup job several times
a day. `KEEP_LAST` has to match the points you want (28 increments is a week
of 6-hour points).

With the shipped **Avol**:

* every 6 hours is ok-ish (the miss is about a tenth of the interval);
* every 4 hours is just rough (about 15 percent, and a burst in the last 35
  minutes can be a large part of that increment).

To put a 4-hour job back in the ok-ish band, **Avol** needs to be at most
about 30 minutes (**T/8**), which is the shipped setting only if the helper
is actually refreshing. To make it sound (**T/12**), set
`SP_VOLUMESSPACE_SECONDS` so that **Avol** is at most 20 minutes. The
snapshots being flattened are only a few hours old. Keep **Asnap** below
**T** as well, or the flatten falls back to the recorded sizes and an earlier
undercount sticks.

The scheme is not feasible once **Avol** reaches the backup interval: 4 hours
if the job is 4-hourly, 6 hours if it is 6-hourly. The increments are then 0.

### Hourly incremental

`MODE=INCREMENT`, **T** = 1 hour, local.

With the shipped **Avol** the miss can be half the hour. A VM that writes in
the second half of the hour records an increment near 0. That is a rough
figure, not something to bill on or to alert on. It becomes ok-ish only when
**Avol** is at most about 7 or 8 minutes (**T/8**), which means
`SP_VOLUMESSPACE_SECONDS` down near the helper period so `VolumesSpace` runs
every few minutes. Even then a burst inside that window is missing. Hourly
with the shipped 1800 is the wrong combination if the size has to mean the
hour's writes.

At **Avol** of an hour or more the hourly increment is not feasible (0).

### More often than the cache

Every 15 or 30 minutes, or any job with **T ≤ Avol**. With the shipped cache
that is every job at about 35 minutes or faster. Later increments are 0, or
a sample from just after the previous snapshot. `KEEP_LAST`, flatten, and a
shorter OpenNebula monitoring interval do not recover it. The only parameter
that makes it feasible is an **Avol** below **T**, and for ok-ish an **Avol**
at or below **T/8**. At a 15-minute schedule that is a cache interval of
about 2 minutes, which the 4-minute helper cannot deliver. A 15-minute
incremental size is not feasible on this driver. The snapshots themselves
are taken and can be restored.

### Remote daily full

`MODE=FULL`, daily, `KEEP_LAST=7`, `SP_BACKUP_LOCATION` set. The usual DR
layout.

Each image is the logical content, stale by **Avol**, same as a local full.
The quota is about 7 logical copies. The target stores one copy plus the
daily deltas. `USED_MB` shows those deltas when the location is a cluster of
this multi-cluster, late by **Asnap**. A location that is not a cluster in
this multi-cluster shows zeros forever, so OpenNebula has no usage figure
for that site at all.

Ok-ish as "each restore point is about the size of the VM," under the same
**Avol** conditions as a local full. Not a measure of bytes transferred or of
bytes kept on the far side. Retention frees the far side only when that
site's bridge entry has `minimumDeleteDelay`. Without it the copies stay, and
a cluster target's `USED_MB` keeps them after OpenNebula has dropped the
images.

### Remote daily incremental

`MODE=INCREMENT`, daily, `KEEP_LAST` set, `SP_BACKUP_LOCATION` set.

This is the scheme that looks incremental and is billed as full copies. Each
increment is the full logical content. With `KEEP_LAST=7` the quota settles
near 7 times the VM and stays there. The target's extra cost per day is the
day's delta. No value of `SP_DEFAULT_SECONDS` fixes the quota. `KEEP_LAST=1`
is the only setting that brings the image back to a single full copy, and
then there is no increment history in OpenNebula.

Not feasible for quotas or for showing users a size. Feasible as a backup:
the restore points are real, and a cluster target's `USED_MB` is the physical
side. Prefer remote `FULL` with an explicit `KEEP_LAST` when someone will
read the image size. Prefer a local incremental chain when the quota has to
track growth.

## Choosing

| Scheme | Shipped cache (A ≈ 35 min) | Stays ok-ish while | Not feasible when |
|---|---|---|---|
| Local daily full, `KEEP_LAST` 7–30 | Ok for logical size and quotas | Writes during **Avol** are a small part of the VM | **Avol** is days, or the helper never lists the disks (virtual size) |
| Local weekly full | Ok, same rule | Same | Same |
| Local daily incremental, `KEEP_LAST` 7–14 | Sound | **Avol** up to about 2 h, still fair to about 3 h | **Avol** ≥ 24 h, or the helper is down (increments stay 0) |
| Local incremental every 6 h | Ok-ish | **Avol** ≤ about 45 min | **Avol** ≥ 6 h |
| Local incremental every 4 h | Rough | **Avol** ≤ about 30 min (sound at ≤ 20 min) | **Avol** ≥ 4 h |
| Local hourly incremental | Rough, a poor quota | **Avol** ≤ about 8 min | **Avol** ≥ 1 h |
| Local incremental at ≤ **Avol** | Not feasible (size 0) | **Avol** ≤ **T/8**, and **T** above the 4 min helper | **T** ≤ **Avol**. A 15 min job cannot get there |
| Remote daily full | Ok as "one VM per restore point" | Same as local full, for that reading | You needed the bytes on the target. A non-cluster location shows 0 |
| Remote daily incremental | Quota ≈ `KEEP_LAST` full copies | Never, for a delta or a single-copy bill | Any cache setting. `KEEP_LAST=1` is a single full copy and no history |

The backup works on every row. The size is worth showing to users, and worth
a quota, on local full at a daily or weekly pace, and on local daily
incremental with the shipped cache and `KEEP_LAST`. It is a rough hint on
4-to-6-hour local incrementals with the shipped cache. It is the wrong tool
for hourly or faster incrementals unless `SP_VOLUMESSPACE_SECONDS` is brought
down to match **T**, and for any remote incremental chain.
