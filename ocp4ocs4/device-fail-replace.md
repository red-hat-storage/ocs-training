This process should be followed when an OSD **Pod** is in an `Error`
state and the root cause is a failed underlying storage device.

Login to **OpenShift Web Console** and view the storage Dashboard.

![OCP Storage Dashboard status after OSD
failed](https://access.redhat.com/sites/default/files/attachments/ocs4-ocp-dashboard-status-bad.png)

Make sure to have the Rook-Ceph `toolbox` **Pod** available.
Instructions for deploying the `toolbox` can be found in
[How to configure Ceph toolbox in OpenShift Container Storage 4.x](https://access.redhat.com/articles/4628891).

Removing failed OSD from Ceph cluster
-------------------------------------

The first step is to identify the OCP node that has the bad OSD
scheduled on it. In this example it is OCP node `compute-2`.

    # oc get -n openshift-storage pods -o wide | grep osd | grep -v prepare

**Example output:.**

    rook-ceph-osd-0-6d77d6c7c6-m8xj6                                  0/1     CrashLoopBackOff        0          24h   10.129.0.16   compute-2   <none>           <none>
    rook-ceph-osd-1-85d99fb95f-2svc7                                  1/1     Running               0          24h   10.128.2.24   compute-0   <none>           <none>
    rook-ceph-osd-2-6c66cdb977-jp542                                  1/1     Running               0          24h   10.130.0.18   compute-1   <none>           <none>

Now that the OCP node has been identified you will log into the
`toolbox` **Pod**.

    # TOOLS_POD=$(oc get pods -n openshift-storage -l app=rook-ceph-tools -o name)
    # oc rsh -n openshift-storage $TOOLS_POD

    # ceph osd tree

**Example output.**

    ID  CLASS WEIGHT  TYPE NAME                            STATUS REWEIGHT PRI-AFF
     -1       0.29008 root default
     -4       0.09669     rack rack0
     -3       0.09669         host ocs-deviceset-0-0-nvs68
      0   hdd 0.09669             osd.0                      down  1.00000 1.00000
     -8       0.09669     rack rack1
     -7       0.09669         host ocs-deviceset-1-0-959rp
      1   hdd 0.09669             osd.1                        up  1.00000 1.00000
    -12       0.09669     rack rack2
    -11       0.09669         host ocs-deviceset-2-0-79j94
      2   hdd 0.09669             osd.2                        up  1.00000 1.00000

The following process will remove the **down** OSD from the cluster so a
new OSD can be added.

    # ceph osd out {osd-id}

**Example output.**

    marked out osd.0.

After the OSD is marked out the `OSD REWEIGHT RATIO` is set to `zero`.
This will cause the data to migrate from this OSD to the remaining OSDs.

In the case of only three OSDs the data cannot migrate because there is
only one OSD in each of the 3 availability zones and only 2 OSDs are
operational.

    # ceph osd tree

**Example output.**

    ID  CLASS WEIGHT  TYPE NAME                            STATUS REWEIGHT PRI-AFF
     -1       0.29008 root default
     -4       0.09669     rack rack0
     -3       0.09669         host ocs-deviceset-0-0-nvs68
      0   hdd 0.09669             osd.0                      down        0 1.00000
     -8       0.09669     rack rack1
     -7       0.09669         host ocs-deviceset-1-0-959rp
      1   hdd 0.09669             osd.1                        up  1.00000 1.00000
    -12       0.09669     rack rack2
    -11       0.09669         host ocs-deviceset-2-0-79j94
      2   hdd 0.09669             osd.2                        up  1.00000 1.00000

In the case where the data can be migrated off the OSD in a `Error`
state, you will want to wait until all **PGs** are `active+clean`.

    # ceph pg stat

**Example output for all data (PGs) migrating off of OSD.**

    192 pgs: 192 active+clean;
    380 MiB data, 1015 MiB used, 1.5 TiB / 1.5 TiB avail;
    1.2 KiB/s rd, 59 KiB/s wr, 8 op/s

Now this OSD needs to be removed from the Ceph cluster.

    # ceph osd purge {osd-id} --yes-i-really-mean-it

**Example output.**

    purged osd.0

Now check to see that the OSD is removed.

    # ceph osd tree

**Example output for 3 OSD cluster after osd.0 purged.**

    ID  CLASS WEIGHT  TYPE NAME                            STATUS REWEIGHT PRI-AFF
     -1       0.19339 root default
     -4             0     rack rack0
     -3             0         host ocs-deviceset-0-0-nvs68
     -8       0.09669     rack rack1
     -7       0.09669         host ocs-deviceset-1-0-959rp
      1   hdd 0.09669             osd.1                        up  1.00000 1.00000
    -12       0.09669     rack rack2
    -11       0.09669         host ocs-deviceset-2-0-79j94
      2   hdd 0.09669             osd.2                        up  1.00000 1.00000

You can now exit the toolbox by either pressing kbd:\[Ctrl+D\] or by
executing

    # exit

Delete PVC resources associated with failed OSD
-----------------------------------------------

First the **DeviceSet** must be identified that is associated with the
failed OSD. In this example the **PVC** name is
`ocs-deviceset-0-0-nvs68`.

    # oc get -o yaml -n openshift-storage deployment rook-ceph-osd-{osd-id} | grep ceph.rook.io/pvc

**Example output.**

    ceph.rook.io/pvc: ocs-deviceset-0-0-nvs68
    ceph.rook.io/pvc: ocs-deviceset-0-0-nvs68

Scale down failed OSD **deployment** to `replicas=0`. In this example
the deployment name is `rook-ceph-osd-0`.

    # oc scale -n openshift-storage deployment rook-ceph-osd-{osd-id} --replicas=0

**Example output.**

    deployment.extensions/rook-ceph-osd-0 scaled

Now identify the **PV** associated with the **PVC** identified earlier.
In this example the associated **PV** is `local-pv-d9c5cbd6`.

    # oc get -n openshift-storage pvc ocs-deviceset-0-0-nvs68

**Example output.**

    NAME                      STATUS        VOLUME              CAPACITY   ACCESS MODES   STORAGECLASS   AGE
    ocs-deviceset-0-0-nvs68   Bound   local-pv-d9c5cbd6   100Gi      RWO            localblock     24h

Now the failed device name needs to be identified. In this example the
device name is `sdb`.

    # oc get pv local-pv-d9c5cbd6 -o yaml | grep path

**Example output.**

    path: /mnt/local-storage/localblock/sdb

The next step is to identify the `prepare-pod` associated with the
failed OSD.

    # oc describe -n openshift-storage pvc ocs-deviceset-0-0-nvs68 | grep Mounted

**Example output.**

    Mounted By:    rook-ceph-osd-prepare-ocs-deviceset-0-0-nvs68-zblp7

This `prepare-pod` must be deleted before the associated **PVC** can be
removed.

    # oc delete -n openshift-storage pod rook-ceph-osd-prepare-ocs-deviceset-0-0-nvs68-zblp7

**Example output.**

    pod "rook-ceph-osd-prepare-ocs-deviceset-0-0-nvs68-zblp7" deleted

Now the **PVC** associated with the failed OSD can be deleted.

    # oc delete -n openshift-storage pvc -n openshift-storage ocs-deviceset-0-0-nvs68

**Example output.**

    persistentvolumeclaim "ocs-deviceset-0-0-nvs68" deleted

Replace failed drive and create new PV
--------------------------------------

After the **PVC** associated with the failed drive is deleted, it is
time to replace the failed drive and use this new drive to create a new
OCP **PV**.

First step is to login to the OCP node with the failed drive and record
the `/dev/disk/by-id/{id}` that is to be replaced. In this example the
OCP node is `compute-2`.

    # oc debug node/compute-2

**Example output.**

    Starting pod/compute-2-debug ...
    To use host binaries, run `chroot /host`
    Pod IP: 10.70.56.66
    If you don't see a command prompt, try pressing enter.
    sh-4.2# chroot /host

Using the device name identified earlier, `sdb`, record the
`/dev/disk/by-id/{id}` for use in the next step.

    sh-4.4# ls -alh /mnt/local-storage/localblock

**Example output.**

    total 0
    drwxr-xr-x. 2 root root 17 Apr  8 23:03 .
    drwxr-xr-x. 3 root root 24 Apr  8 23:03 ..
    lrwxrwxrwx. 1 root root 54 Apr  8 23:03 sdb -> /dev/disk/by-id/scsi-36000c2962b2f613ba1f8f4c5cf952237

Identify the device name for the new drive. In this example `sdd`.

    sh-4.4# lsblk

**Example output.**

    NAME                         MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
    sda                            8:0    0   60G  0 disk
    |-sda1                         8:1    0  384M  0 part /boot
    |-sda2                         8:2    0  127M  0 part /boot/efi
    |-sda3                         8:3    0    1M  0 part
    `-sda4                         8:4    0 59.5G  0 part
      `-coreos-luks-root-nocrypt 253:0    0 59.5G  0 dm   /sysroot
    sdb                            8:16   0  100G  0 disk
    `-ceph--c1d5448f--d79b--4778--977c--49a6b50d700a-osd--block--f85be71c--98f5--49c3--bf6f--1f1e3645d251
                                 253:1    0   99G  0 lvm
    sdc                            8:32   0   10G  0 disk /var/lib/kubelet/pods/df23429b-6dad-4d8c-b705-22871ba979de/vol
    sdd                            8:48   0  100G  0 disk

Now identify the `/dev/disk/by-id/{id}` for the new drive and record for
use in the next step.

    sh-4.2# ls -alh /dev/disk/by-id | grep sdd

**Example output.**

    lrwxrwxrwx. 1 root root   9 Apr  9 20:45 scsi-36000c29f5c9638dec9f19b220fbe36b1 -> ../../sdd
    lrwxrwxrwx. 1 root root   9 Apr  9 20:45 wwn-0x6000c29f5c9638dec9f19b220fbe36b1 -> ../../sdd

After the new `/dev/disk/by-id/{id}` is available a new disk entry can
be added to the **LocalVolume** CR.

    # oc get -n local-storage localvolume

**Example output.**

    NAME          AGE
    local-block   25h

Edit **LocalVolume** CR and remove or comment out failed device
`/dev/disk/by-id/{id}` and add the new `/dev/disk/by-id/{id}`. In this
example the new device is
`/dev/disk/by-id/scsi-36000c29f5c9638dec9f19b220fbe36b1`.

    # oc edit -n local-storage localvolume local-block

**Example output.**

    [...]
      storageClassDevices:
      - devicePaths:
        - /dev/disk/by-id/scsi-36000c29346bca85f723c4c1f268b5630
        - /dev/disk/by-id/scsi-36000c29134dfcfaf2dfeeb9f98622786
    #   - /dev/disk/by-id/scsi-36000c2962b2f613ba1f8f4c5cf952237
        - /dev/disk/by-id/scsi-36000c29f5c9638dec9f19b220fbe36b1
        storageClassName: localblock
        volumeMode: Block
    [...]

Make sure to save the changes after editing using kbd:\[:wq!\].

Validate that there is new `Available` **PV** of correct size and that
the old **PV** is now in a `Released` state.

    # oc get pv | grep 100Gi

**Example output.**

    local-pv-3e8964d3                          100Gi      RWO            Delete           Bound       openshift-storage/ocs-deviceset-2-0-79j94   localblock                             25h
    local-pv-414755e0                          100Gi      RWO            Delete           Bound       openshift-storage/ocs-deviceset-1-0-959rp   localblock                             25h
    local-pv-b481410                           100Gi      RWO            Delete           Available                                               localblock                             3m24s
    local-pv-d9c5cbd6                          100Gi      RWO            Delete           Released    openshift-storage/ocs-deviceset-0-0-nvs68   localblock

Login to OCP node with failed device and remove the old symlink.
Validate it is removed before proceeding.

    # oc debug node/compute-2

**Example output.**

    Starting pod/compute-2-debug ...
    To use host binaries, run `chroot /host`
    Pod IP: 10.70.56.66
    If you don't see a command prompt, try pressing enter.
    sh-4.2# chroot /host

Identify the old `symlink` for the failed device name. In this example
the failed device name is `sdb`.

    sh-4.4# ls -alh /mnt/local-storage/localblock

**Example output.**

    total 0
    drwxr-xr-x. 2 root root 28 Apr 10 00:42 .
    drwxr-xr-x. 3 root root 24 Apr  8 23:03 ..
    lrwxrwxrwx. 1 root root 54 Apr  8 23:03 sdb -> /dev/disk/by-id/scsi-36000c2962b2f613ba1f8f4c5cf952237
    lrwxrwxrwx. 1 root root 54 Apr 10 00:42 sdd -> /dev/disk/by-id/scsi-36000c29f5c9638dec9f19b220fbe36b1

Remove the `symlink`.

    sh-4.4# rm /mnt/local-storage/localblock/sdb

Validate the `symlink` is removed.

    sh-4.4# ls -alh /mnt/local-storage/localblock

**Example output.**

    total 0
    drwxr-xr-x. 2 root root 17 Apr 10 00:56 .
    drwxr-xr-x. 3 root root 24 Apr  8 23:03 ..
    lrwxrwxrwx. 1 root root 54 Apr 10 00:42 sdd -> /dev/disk/by-id/scsi-36000c29f5c9638dec9f19b220fbe36b1

Create new OSD for new device
-----------------------------

Start by deleting the **PV** associated with the failed device. This
**PV** name was identified in an earlier step. In this example the
**PV** name is `local-pv-d9c5cbd6`.

    # oc delete pv local-pv-d9c5cbd6

**Example output.**

    persistentvolume "local-pv-d9c5cbd6" deleted

Verify **PV** for the failed drive is now gone. There should still be an
`Available` **PV** for the new drive.

    # oc get pv | grep 100Gi

**Example output.**

    local-pv-3e8964d3                          100Gi      RWO            Delete           Bound       openshift-storage/ocs-deviceset-2-0-79j94   localblock                             1d20h
    local-pv-414755e0                          100Gi      RWO            Delete           Bound       openshift-storage/ocs-deviceset-1-0-959rp   localblock                             1d20h
    local-pv-b481410                           100Gi      RWO            Delete           Available                                               localblock                             1d18h

Next step is to delete the **deployment** for the failed OSD **Pod**.
This **deployment** was scaled to `replicas=0` in an earlier step.

    # oc get -n openshift-storage deployments | grep osd

**Example output.**

    rook-ceph-osd-0                                      0/0     0            0           1d20h
    rook-ceph-osd-1                                      1/1     1            1           1d20h
    rook-ceph-osd-2                                      1/1     1            1           1d20h

For this example the deployment name is `rook-ceph-osd-0`.

    # oc delete -n openshift-storage deployment rook-ceph-osd-{osd-id}

**Example output.**

    deployment.extensions "rook-ceph-osd-0" deleted

Now that the **deployment** and all other associated OCP and Ceph
resources for the failed device are deleted or removed, the new OSD can
be deployed. This is done by restarting the `rook-ceph-operator` to
force operator reconciliation.

    # oc get -n openshift-storage pod -l app=rook-ceph-operator

**Example output.**

    NAME                                  READY   STATUS    RESTARTS   AGE
    rook-ceph-operator-6f74fb5bff-2d982   1/1     Running   0          1d20h

Now delete the `rook-ceph-operator`.

    # oc -n openshift-storage delete pod rook-ceph-operator-6f74fb5bff-2d982

**Example output.**

    pod "rook-ceph-operator-6f74fb5bff-2d982" deleted

Now validate the `rook-ceph-operator` **Pod** is restarted.

    # oc get -n openshift-storage pod -l app=rook-ceph-operator

**Example output.**

    NAME                                  READY   STATUS    RESTARTS   AGE
    rook-ceph-operator-6f74fb5bff-7mvrq   1/1     Running   0          66s

Last step is to validate there is a new OSD, that Ceph is healthy, and
that a successful replacement shows in the **OpenShift Web Console**
Dashboards.

    # oc -n openshift-storage get pods | grep osd | grep -v prepare

**Example output.**

    rook-ceph-osd-0-5f7f4747d4-snshw                                  1/1     Running     0          4m47s
    rook-ceph-osd-1-85d99fb95f-2svc7                                  1/1     Running     0          1d20h
    rook-ceph-osd-2-6c66cdb977-jp542                                  1/1     Running     0          1d20h

There now is a OSD that was redeployed with a similar name,
`rook-ceph-osd-0`.

Next step is to login to Ceph and see if the cluster is healthy.

    # TOOLS_POD=$(oc get pods -n openshift-storage -l app=rook-ceph-tools -o name)
    # oc rsh -n openshift-storage $TOOLS_POD

    # ceph status

**Example output.**

      cluster:
        id:     fc89e00e-959e-486b-aff1-d9734778e9e0
        health: HEALTH_OK

      services:
        mon: 3 daemons, quorum a,b,c (age 2d)
        mgr: a(active, since 2d)
        mds: ocs-storagecluster-cephfilesystem:1 {0=ocs-storagecluster-cephfilesystem-a=up:active} 1 up:standby-replay
        osd: 3 osds: 3 up (since 11m), 3 in (since 11m)
        rgw: 1 daemon active (ocs.storagecluster.cephobjectstore.a)

      task status:

      data:
        pools:   10 pools, 192 pgs
        objects: 479 objects, 673 MiB
        usage:   4.9 GiB used, 292 GiB / 297 GiB avail
        pgs:     192 active+clean

      io:
        client:   853 B/s rd, 38 KiB/s wr, 1 op/s rd, 5 op/s wr

We can see the Ceph health is `HEALTH_OK`.

You can now exit the toolbox by either pressing kbd:\[Ctrl+D\] or by
executing

    # exit

Now login to **OpenShift Web Console** and view the storage Dashboard.

![OCP Storage Dashboard status after OSD
replacement](https://access.redhat.com/sites/default/files/attachments/ocs4-ocp-dashboard-status.png)
