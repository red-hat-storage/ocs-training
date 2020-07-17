# OpenShift Container Storage:  Replacing a Drive

This process should be followed when an OSD **Pod** is in an `Error`
or `CrashLoopBackOff` state and the root cause is a failed underlying storage device. This process can also be used to replace a healthy drive.

## Removing failed OSD from Ceph cluster

1. The first step is to identify the OCP node that has the bad OSD scheduled on it.

    ```
    oc get -n openshift-storage pods -l app=rook-ceph-osd -o wide
    ```
    **Example output:.**
    ```
    rook-ceph-osd-0-6d77d6c7c6-m8xj6                                  0/1     CrashLoopBackOff      0          24h   10.129.0.16   compute-2   <none>           <none>
    rook-ceph-osd-1-85d99fb95f-2svc7                                  1/1     Running               0          24h   10.128.2.24   compute-0   <none>           <none>
    rook-ceph-osd-2-6c66cdb977-jp542                                  1/1     Running               0          24h   10.130.0.18   compute-1   <none>           <none>
    ```

2. In this example, `rook-ceph-osd-0-6d77d6c7c6-m8xj6` needs to be replaced and `compute-2` is the OCP node on which the OSD is scheduled. If the OSD to be replaced is healthy, the status of the pod will be Running.

    ```
    osd_id_to_remove=0
    oc scale -n openshift-storage deployment rook-ceph-osd-${osd_id_to_remove} --replicas=0
    ```

    **Example output.**
    ```
    deployment.extensions/rook-ceph-osd-0 scaled
    ```
3. Verify that the rook-ceph-osd pod is terminated.
    ```
    oc get -n openshift-storage pods -l ceph-osd-id=${osd_id_to_remove}
    ```
    The pod should be deleted.
	
    ```
    No resources found in openshift-storage namespace.
    ```

4. The following commands will remove a OSD from the cluster so a new OSD can be added.

    **Change OSD_ID_TO_REMOVE in the first line below for the failed OSD.**
    In this example, OSD "0" is to be removed. The OSD ID is the integer in the pod name immediately after the "rook-ceph-osd-" prefix.

    ```
    oc process -n openshift-storage ocs-osd-removal -p FAILED_OSD_ID=${osd_id_to_remove} | oc create -f -
    ```

    A job will be started to remove the OSD. The job should complete within several seconds. To view the results of the job, retrieve the logs of the pod associated with the job:

    ```
    oc logs -n openshift-storage ocs-osd-removal-${osd_id_to_remove}-<pod-suffix>
    ```

     **Example output.**
     ```
	++ grep 'osd.0 '
	++ ceph osd tree
	++ awk '{print $5}'
	+ osd_status=down
	OSD 0 is down. Proceeding to mark out and purge
	+ [[ down == \u\p ]]
	+ echo 'OSD 0 is down. Proceeding to mark out and purge'
	+ ceph osd out osd.0
	marked out osd.0. 
	+ ceph osd purge osd.0 --force --yes-i-really-mean-it
	purged osd.0
    ```

## Delete PVC resources associated with failed OSD

1. First the **DeviceSet** must be identified that is associated with the failed OSD.

    ```
    oc get -n openshift-storage -o yaml deployment rook-ceph-osd-${osd_id_to_remove} | grep ceph.rook.io/pvc
    ```

    **Example output.**
    ```
    ceph.rook.io/pvc: ocs-deviceset-0-0-nvs68
        ceph.rook.io/pvc: ocs-deviceset-0-0-nvs68
    ```

2. Now identify the **PV** associated with the **PVC** identified earlier. Make sure to use your PVC name identified in prior step.

    ```
    oc get -n openshift-storage pvc ocs-deviceset-0-0-nvs68
    ```

    **Example output.**
    ```
    NAME                      STATUS        VOLUME        CAPACITY   ACCESS MODES   STORAGECLASS   AGE
    ocs-deviceset-0-0-nvs68   Bound   local-pv-d9c5cbd6   100Gi      RWO            localblock     24h
    ```

3. Now the failed device name needs to be identified. Make sure to use your PV name identified in prior step. Record the device name for a future step (i.e., sdb).

    ```
    oc get pv local-pv-d9c5cbd6 -o yaml | grep path
    ```

    **Example output.**
    ```
    path: /mnt/local-storage/localblock/sdb
    ```

4. The next step is to identify the `prepare-pod` associated with the removed OSD. Make sure to use your PVC name identified in prior step.

    ```
    oc describe -n openshift-storage pvc ocs-deviceset-0-0-nvs68 | grep Mounted
    ```

    **Example output.**
    ```
    Mounted By:    rook-ceph-osd-prepare-ocs-deviceset-0-0-nvs68-zblp7
    ```
	
    This `osd-prepare` pod must be deleted before the associated **PVC** can be removed.

    ```
    oc delete -n openshift-storage pod rook-ceph-osd-prepare-ocs-deviceset-0-0-nvs68-zblp7
    ```

    **Example output.**

    ```
    pod "rook-ceph-osd-prepare-ocs-deviceset-0-0-nvs68-zblp7" deleted
    ```

5. Now the **PVC** associated with the failed OSD can be deleted.

    ```
    oc delete -n openshift-storage pvc ocs-deviceset-0-0-nvs68
    ```

    **Example output.**
    ```
    persistentvolumeclaim "ocs-deviceset-0-0-nvs68" deleted
    ```
## Replace failed drive and create new PV

After the **PVC** associated with the failed drive is deleted, it is
time to replace the failed drive and use this new drive to create a new
OCP **PV**.

First step is to login to the OCP node with the failed drive and record
the `/dev/disk/by-id/{id}` that is to be replaced. In this example the
OCP node is `compute-2`.

```
oc debug node/compute-2
```

**Example output.**

    Starting pod/compute-2-debug ...
    To use host binaries, run `chroot /host`
    Pod IP: 10.70.56.66
    If you don't see a command prompt, try pressing enter.
    sh-4.2# chroot /host

Using the device name identified earlier, `sdb`, record the
`/dev/disk/by-id/{id}` for use in the next step.

```
sh-4.4# ls -alh /mnt/local-storage/localblock
```
**Example output.**

    total 0
    drwxr-xr-x. 2 root root 17 Apr  8 23:03 .
    drwxr-xr-x. 3 root root 24 Apr  8 23:03 ..
    lrwxrwxrwx. 1 root root 54 Apr  8 23:03 sdb -> /dev/disk/by-id/scsi-36000c2962b2f613ba1f8f4c5cf952237

Identify the device name for the new drive. In this example `sdd`.

```
sh-4.4# lsblk
```

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

```
sh-4.2# ls -alh /dev/disk/by-id | grep sdd
```

**Example output.**

    lrwxrwxrwx. 1 root root   9 Apr  9 20:45 scsi-36000c29f5c9638dec9f19b220fbe36b1 -> ../../sdd
    lrwxrwxrwx. 1 root root   9 Apr  9 20:45 wwn-0x6000c29f5c9638dec9f19b220fbe36b1 -> ../../sdd

After the new `/dev/disk/by-id/{id}` is available a new disk entry can
be added to the **LocalVolume** CR.


```
oc get -n local-storage localvolume
```
**Example output.**

    NAME          AGE
    local-block   25h

Edit **LocalVolume** CR and remove or comment out failed device
`/dev/disk/by-id/{id}` and add the new `/dev/disk/by-id/{id}`. In this
example the new device is
`/dev/disk/by-id/scsi-36000c29f5c9638dec9f19b220fbe36b1`.

```
oc edit -n local-storage localvolume local-block
```

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

```
oc get pv | grep 100Gi
```

**Example output.**
```
local-pv-3e8964d3                          100Gi      RWO            Delete           Bound       openshift-storage/ocs-deviceset-2-0-79j94   localblock                             25h
local-pv-414755e0                          100Gi      RWO            Delete           Bound       openshift-storage/ocs-deviceset-1-0-959rp   localblock                             25h
local-pv-b481410                           100Gi      RWO            Delete           Available                                               localblock                             3m24s
local-pv-d9c5cbd6                          100Gi      RWO            Delete           Released    openshift-storage/ocs-deviceset-0-0-nvs68   localblock
```
	Now delete the PV.
    
	```
	oc delete pv local-pv-d9c5cbd6
	```
	
	**Example output.**
	```
	persistentvolume "local-pv-d9c5cbd6" deleted
	```
	
Login to OCP node with failed device and remove the old symlink.
Validate it is removed before proceeding.

```
oc debug node/compute-2
```

**Example output.**

    Starting pod/compute-2-debug ...
    To use host binaries, run `chroot /host`
    Pod IP: 10.70.56.66
    If you don't see a command prompt, try pressing enter.
    sh-4.2# chroot /host

Identify the old `symlink` for the failed device name. In this example
the failed device name is `sdb`.

```
sh-4.4# ls -alh /mnt/local-storage/localblock
```

**Example output.**

```
total 0
drwxr-xr-x. 2 root root 28 Apr 10 00:42 .
drwxr-xr-x. 3 root root 24 Apr  8 23:03 ..
lrwxrwxrwx. 1 root root 54 Apr  8 23:03 sdb -> /dev/disk/by-id/scsi-36000c2962b2f613ba1f8f4c5cf952237
lrwxrwxrwx. 1 root root 54 Apr 10 00:42 sdd -> /dev/disk/by-id/scsi-36000c29f5c9638dec9f19b220fbe36b1
```

Remove the `symlink`.

```
sh-4.4# rm /mnt/local-storage/localblock/sdb
```

Validate the `symlink` is removed.

```
sh-4.4# ls -alh /mnt/local-storage/localblock
```

**Example output.**
```
total 0
drwxr-xr-x. 2 root root 17 Apr 10 00:56 .
drwxr-xr-x. 3 root root 24 Apr  8 23:03 ..
lrwxrwxrwx. 1 root root 54 Apr 10 00:42 sdd -> /dev/disk/by-id/scsi-36000c29f5c9638dec9f19b220fbe36b1
```

## Create new OSD for new device
Now that the all associated OCP and Ceph
resources for the failed device are deleted or removed, the new OSD can
be deployed. This is done by restarting the `rook-ceph-operator` to
force operator reconciliation.

    # oc get -n openshift-storage pod -l app=rook-ceph-operator

**Example output.**

    NAME                                  READY   STATUS    RESTARTS   AGE
    rook-ceph-operator-6f74fb5bff-2d982   1/1     Running   0          1d20h

Now delete the `rook-ceph-operator`.

    # oc delete -n openshift-storage pod rook-ceph-operator-6f74fb5bff-2d982

**Example output.**

    pod "rook-ceph-operator-6f74fb5bff-2d982" deleted

Now validate the `rook-ceph-operator` **Pod** is restarted.

    # oc get -n openshift-storage pod -l app=rook-ceph-operator

**Example output.**

    NAME                                  READY   STATUS    RESTARTS   AGE
    rook-ceph-operator-6f74fb5bff-7mvrq   1/1     Running   0          66s

Creation of the new OSD may take several minutes after the operator starts.

Last step is to validate there is a new OSD, that Ceph is healthy, and
that a successful replacement shows in the **OpenShift Web Console**
Dashboards.

    # oc get -n openshift-storage pods -l app=rook-ceph-osd

**Example output.**

    rook-ceph-osd-0-5f7f4747d4-snshw                                  1/1     Running     0          4m47s
    rook-ceph-osd-1-85d99fb95f-2svc7                                  1/1     Running     0          1d20h
    rook-ceph-osd-2-6c66cdb977-jp542                                  1/1     Running     0          1d20h

There now is a OSD that was redeployed with a similar name,
`rook-ceph-osd-0`.

## Removing all OSDs from a failed node

If an entire node has failed, the same procedure in the above section can be followed for all OSDs
on the failed node with the following consideration:
- If the node is not responding, the node must be removed from OCP before the resources
  such as pods and PVs can be deleted. Otherwise, the resources will remain in `terminating` state.
