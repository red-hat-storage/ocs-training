# How to downsize Red Hat OpenShift Container Storage 4.X internal cluster
This document is to supplement the OpenShift Container Storage (OCS) documentation for versions 4.4 or higher and provide instructions for downsizing a previously deployed internal mode cluster. It is not clear at this point when this procedure will be officially documented nor when it will be automated via the `rook-ceph` operator.

This document currently details the step for a dynamically provisioned OCS cluster through the `gp2` (AWS) or `thin` (VMWare) storage class regardless of the OSD device size.

This is a live document to be used in various environments and configurations. If you find any mistakes or missing instructions, please feel free to comment on this KCS or contact Annette Clewett (aclewett@redhat.com) and JC Lopez (jelopez@redhat.com) via email.

## Overview
Red Hat Ceph Storage offers the ability to safely shrink an existing cluster by removing OSDs or MONs but this functionality is not documented for OCS. The purpose of this document is to detail the steps required to safely reduce the number of OSDs in an OCS internal cluster. Such a situation may be faced when an application is migrated or removed from the cluster and the OCP administrator would like to reduce the number of resources used by the OCS cluster (`gp2` persistent volumes, CPU, and RAM consumed by OSDs that are no longer needed).

## Prerequisites
These requirements need to be met before proceeding:
1. An OCS 4.4 or higher internal cluster 
2. The OCS cluster is healthy and all data is protected
3. The OCS cluster contains 6 or more OSDs

## Procedure

### Identify Existing storageDeviceSets
As a starting point we recommend to display and keep at hand a complete list of the pods running in the `openshift-storage` namespace.

~~~
$ oc get pods
NAME                                                              READY   STATUS      RESTARTS   AGE
csi-cephfsplugin-chl65                                            3/3     Running     0          10m
csi-cephfsplugin-dlp66                                            3/3     Running     0          10m
csi-cephfsplugin-provisioner-6bc8b8cdd9-9ngpk                     5/5     Running     0          10m
csi-cephfsplugin-provisioner-6bc8b8cdd9-lb26q                     5/5     Running     0          10m
csi-cephfsplugin-vknsv                                            3/3     Running     0          10m
csi-rbdplugin-7lkxd                                               3/3     Running     0          10m
csi-rbdplugin-pqllf                                               3/3     Running     0          10m
csi-rbdplugin-provisioner-6b9f9f5bf-6fpsq                         5/5     Running     0          10m
csi-rbdplugin-provisioner-6b9f9f5bf-zrq6f                         5/5     Running     0          10m
csi-rbdplugin-tdt7z                                               3/3     Running     0          10m
noobaa-core-0                                                     1/1     Running     0          6m40s
noobaa-db-0                                                       1/1     Running     0          6m40s
noobaa-endpoint-5dbcd54d4f-f74h7                                  1/1     Running     0          4m58s
noobaa-operator-6c57586b78-48j4r                                  1/1     Running     0          11m
ocs-operator-748d9d4469-hhhwk                                     1/1     Running     0          11m
rook-ceph-crashcollector-ip-10-0-129-185-c647fffb5-47r5n          1/1     Running     0          7m42s
rook-ceph-crashcollector-ip-10-0-187-112-b7bddbdc7-69wqv          1/1     Running     0          8m11s
rook-ceph-crashcollector-ip-10-0-207-213-6f5f89698-k2crd          1/1     Running     0          8m27s
rook-ceph-drain-canary-638c3cea6f3692016381c125ab06a1e5-bdmbjvg   1/1     Running     0          6m49s
rook-ceph-drain-canary-8fa99b779e22a9c5b3fe8f57e15a6416-5d94pfg   1/1     Running     0          6m42s
rook-ceph-drain-canary-de7548f9e9ade4c10e0196400c94bc96-692vxxd   1/1     Running     0          6m50s
rook-ceph-mds-ocs-storagecluster-cephfilesystem-a-d896d595q8zpd   1/1     Running     0          6m27s
rook-ceph-mds-ocs-storagecluster-cephfilesystem-b-7d4594f45zdk7   1/1     Running     0          6m27s
rook-ceph-mgr-a-64fb7ff7c7-d7pzl                                  1/1     Running     0          7m24s
rook-ceph-mon-a-7754ccb656-t9zmh                                  1/1     Running     0          8m27s
rook-ceph-mon-b-6c6f9ccfd-cwbrl                                   1/1     Running     0          8m12s
rook-ceph-mon-c-86b75675f4-zfrnz                                  1/1     Running     0          7m42s
rook-ceph-operator-f44596d6-lh4zq                                 1/1     Running     0          11m
rook-ceph-osd-0-7947c4f995-l4bx4                                  1/1     Running     0          6m49s
rook-ceph-osd-1-7cd6dc86c8-484bw                                  1/1     Running     0          6m51s
rook-ceph-osd-2-6b7659dd58-h5lp7                                  1/1     Running     0          6m42s
rook-ceph-osd-3-cb4b7bb9c-9zncq                                   1/1     Running     0          3m11s
rook-ceph-osd-4-75c8d6894-fp9wb                                   1/1     Running     0          3m10s
rook-ceph-osd-5-7b4f4c6785-kgwb4                                  1/1     Running     0          3m9s
rook-ceph-osd-prepare-ocs-deviceset-0-data-0-hwzhx-577f8          0/1     Completed   0          7m20s
rook-ceph-osd-prepare-ocs-deviceset-0-data-1-q72z4-4xqhv          0/1     Completed   0          3m44s
rook-ceph-osd-prepare-ocs-deviceset-1-data-0-bmpzj-27t5s          0/1     Completed   0          7m19s
rook-ceph-osd-prepare-ocs-deviceset-1-data-1-jv2qk-lpd27          0/1     Completed   0          3m42s
rook-ceph-osd-prepare-ocs-deviceset-2-data-0-d6tch-ld7sd          0/1     Completed   0          7m19s
rook-ceph-osd-prepare-ocs-deviceset-2-data-1-r7dwg-dm5mx          0/1     Completed   0          3m40s
~~~

Before you can downsize your cluster you need to validate how many `storageDeviceSets` have been deployed so you can adjust the value properly. Each `storageDeviceSets` requires 3 OSDs deployed on 3 unique OCP nodes and the minimum number in a cluster is 1.

The following command will provide you with the current number of `storageDeviceSets` configured in your cluster:
~~~
$ deviceset=$(oc get storagecluster -o json | jq '.items[0].spec.storageDeviceSets[0].count')
$ echo ${deviceset}
2
~~~

**Note:** If the `count` of storage `storageDeviceSets` is `1` do **NOT** proceed as this will result in a total data loss in your OCS cluster.

Start a Ceph toolbox pod to verify the health of your internal Ceph cluster.

~~~
$ oc patch OCSInitialization ocsinit -n openshift-storage --type json --patch  '[{ "op": "replace", "path": "/spec/enableCephTools", "value": true }]'
~~~

Verify the status of your cluster.

~~~
$ TOOLS_POD=$(oc get pods -n openshift-storage -l app=rook-ceph-tools -o name)
$ oc exec -n openshift-storage ${TOOLS_POD} -- ceph health
HEALTH_OK
~~~

**Note:** If the status of the cluster is not HEALTH_OK, address any issue prior to proceeding.

### Decrease storageDeviceSets Count

~~~
$ oc patch storagecluster ocs-storagecluster -n openshift-storage --type json --patch '[{ "op": "replace", "path": "/spec/storageDeviceSets/0/count", "value": {n} }]'
~~~

**Note:** Make `{n}` as `${deviceset} - 1`. In this example `{n}` will be a value of `1`. See thee example below.

~~~
$ newset=$((deviceset - 1))
$ oc patch storagecluster ocs-storagecluster -n openshift-storage --type json --patch "[{ "op": "replace", "path": "/spec/storageDeviceSets/0/count", "value": ${newset} }]"
storagecluster.ocs.openshift.io/ocs-storagecluster patched
~~~

Verify the `storagecluster` object has been updated. In the example below we go from 2 to 1 `storageDeviceSets`.

~~~
$ oc get storagecluster -n openshift-storage -o json | jq '.items[0].spec.storageDeviceSets[0].count'
1
~~~

### Take Note of Existing storageDeviceSets and OSDs
Before you can proceed you have to identify the `storageDeviceSets` that are to be removed from your cluster. 

~~~
$ oc get job.batch -n openshift-storage | grep prepare
rook-ceph-osd-prepare-ocs-deviceset-0-data-0-hwzhx   1/1           29s        44m
rook-ceph-osd-prepare-ocs-deviceset-0-data-1-q72z4   1/1           32s        40m
rook-ceph-osd-prepare-ocs-deviceset-1-data-0-bmpzj   1/1           27s        44m
rook-ceph-osd-prepare-ocs-deviceset-1-data-1-jv2qk   1/1           32s        40m
rook-ceph-osd-prepare-ocs-deviceset-2-data-0-d6tch   1/1           36s        44m
rook-ceph-osd-prepare-ocs-deviceset-2-data-1-r7dwg   1/1           28s        40m
~~~

**Note:** Each `storageDeviceSets` has 3 jobs, one per replica. The rank of the `storageDeviceSets` is materialized by the value after `data`. If we look at the job `xxx-deviceset-0-data-0-yyy` it means the job is for the first replica (**`deviceset-0`**) for the first rank (**`data-0`**).

We recommend that you shrink your cluster by removing the higher OSD IDs that are deployed for the higher rank `storageDeviceSets`. To identify the correct OSDs, verify which OSDs have been deployed with the following command.

~~~
$ oc get pods | grep osd | grep -v prepare
rook-ceph-osd-0-7947c4f995-l4bx4                                  1/1     Running     0          49m
rook-ceph-osd-1-7cd6dc86c8-484bw                                  1/1     Running     0          49m
rook-ceph-osd-2-6b7659dd58-h5lp7                                  1/1     Running     0          49m
rook-ceph-osd-3-cb4b7bb9c-9zncq                                   1/1     Running     0          46m
rook-ceph-osd-4-75c8d6894-fp9wb                                   1/1     Running     0          46m
rook-ceph-osd-5-7b4f4c6785-kgwb4                                  1/1     Running     0          46m
~~~

In the example above, the first `storageDeviceSets` correspond to OSDs 0 through 2 while the second `storageDeviceSets` correspond to OSDs 3 through 5. You can verify which `storageDeviceSets` is being used by each OSD using the following command.

~~~
$ oc get pod rook-ceph-osd-5-7b4f4c6785-kgwb4 -n openshift-storage -o json | jq -r '.metadata.labels["ceph.rook.io/pvc"]'
ocs-deviceset-1-data-1-jv2qk
~~~

From the example above the following objects will be removed from the cluster:
* OSD with id 5
* OSD with id 4
* OSD with id 3
* DeviceSet with id ocs-deviceset-2-data-1
* DeviceSet with id ocs-deviceset-1-data-1
* DeviceSet with id ocs-deviceset-0-data-1

### Remove OSDs from the Ceph Cluster
You **MUST** remove each OSD, ONE AT A TIME, using the following set of commands. Make sure the cluster reaches `HEALTH_OK` status before removing the next OSD.

#### Step 1 - Scale down OSD deployment
~~~
$ osd_id_to_remove=5
$ oc scale deployment rook-ceph-osd-${osd_id_to_remove} --replicas=0 -n openshift-storage
deployment.apps/rook-ceph-osd-5 scaled
~~~

Verify OSD pod has been terminated

~~~
$ oc get pods -n openshift-storage | grep osd-${osd_id_to_remove}
~~~

Once the OSD pod has been verified, you can remove the OSD from the Ceph cluster.

#### Step 2 - Removed OSD from Ceph cluster
~~~
$ oc process -n openshift-storage ocs-osd-removal -p FAILED_OSD_ID=${osd_id_to_remove} | oc create -f -
job.batch/ocs-osd-removal-5 created
~~~

#### Step 3 - Check Cluster Status and Data Protection
Check cluster status and wait until the status is `HEALTH_OK`

~~~
$ TOOLS_POD=$(oc get pods -n openshift-storage -l app=rook-ceph-tools -o name)
$ oc exec -n openshift-storage ${TOOLS_POD} -- ceph health
HEALTH_OK
~~~

Check the number of OSDs in the Ceph cluster has decreased.

~~~
$ oc exec -n openshift-storage ${TOOLS_POD} -- ceph osd stat
5 osds: 5 up (since 3m), 5 in (since 95s); epoch: e85
~~~

You can now proceed with the next OSD removal, Step 1, 2 and 3 of this chapter (Remove OSDs from the Ceph Cluster). Simply update the `osd_id_to_remove=` command in Step 1 to match the OSD id.

**Note:** In our test environment we repeated Step 1, 2 and 3 with the following values:

* `osd_id_to_remove=4`
* `osd_id_to_remove=3`

Here are the commands for this example after the first OSD (5) is removed and purged from Ceph.

~~~
$ osd_id_to_remove=4
$ oc scale deployment rook-ceph-osd-${osd_id_to_remove} --replicas=0 -n openshift-storage
deployment.apps/rook-ceph-osd-4 scaled
$ oc get pods -n openshift-storage | grep osd-${osd_id_to_remove}
$ oc process -n openshift-storage ocs-osd-removal -p FAILED_OSD_ID=${osd_id_to_remove} | oc create -f -
job.batch/ocs-osd-removal-4 created
$ oc exec -n openshift-storage ${TOOLS_POD} -- ceph health
HEALTH_OK
$ oc exec -n openshift-storage ${TOOLS_POD} -- ceph osd stat
4 osds: 4 up (since 2m), 4 in (since 46s); epoch: e105
$ osd_id_to_remove=3
$ oc scale deployment rook-ceph-osd-${osd_id_to_remove} --replicas=0 -n openshift-storage
deployment.apps/rook-ceph-osd-3 scaled
$ oc get pods -n openshift-storage | grep osd-${osd_id_to_remove}
$ oc process -n openshift-storage ocs-osd-removal -p FAILED_OSD_ID=${osd_id_to_remove} | oc create -f -
job.batch/ocs-osd-removal-3 created
$ oc exec -n openshift-storage ${TOOLS_POD} -- ceph health
HEALTH_WARN too many PGs per OSD (288 > max 250)
$ oc exec -n openshift-storage ${TOOLS_POD} -- ceph osd stat
3 osds: 3 up (since 99s), 3 in (since 53s); epoch: e120
~~~

**Note:** Although the status of the cluster is not `HEALTH_OK` in the above example no warning or error is reported regarding the protection of the data itself.

### Remove OSD Deployment Objects

Now that the OSDs have been removed from the Ceph cluster and the OSD pods have been removed from the OCP cluster we will remove the deployment object for each OSD we have removed.

~~~
for i in 5 4 3; do oc delete -n openshift-storage deployment.apps/rook-ceph-osd-${i}; done
deployment.apps "rook-ceph-osd-5" deleted
deployment.apps "rook-ceph-osd-4" deleted
deployment.apps "rook-ceph-osd-3" deleted
~~~

### Remove Prepare Jobs

Now that the deployments have been removed we will clean up the prepare jobs that were responsible for preparing the storage devices for the OSDs that no longer exist.

~~~
$ oc get job -n openshift-storage | grep prepare
rook-ceph-osd-prepare-ocs-deviceset-0-data-0-hwzhx   1/1           29s        162m
rook-ceph-osd-prepare-ocs-deviceset-0-data-1-q72z4   1/1           32s        159m
rook-ceph-osd-prepare-ocs-deviceset-1-data-0-bmpzj   1/1           27s        162m
rook-ceph-osd-prepare-ocs-deviceset-1-data-1-jv2qk   1/1           32s        158m
rook-ceph-osd-prepare-ocs-deviceset-2-data-0-d6tch   1/1           36s        162m
rook-ceph-osd-prepare-ocs-deviceset-2-data-1-r7dwg   1/1           28s        158m
~~~

Remove only the jobs corresponding to the `storageDeviceSets` we have removed.

~~~
$ oc delete -n openshift-storage job rook-ceph-osd-prepare-ocs-deviceset-2-data-1-r7dwg
job.batch "rook-ceph-osd-prepare-ocs-deviceset-2-data-1-r7dwg" deleted
$ oc delete -n openshift-storage job rook-ceph-osd-prepare-ocs-deviceset-1-data-1-jv2qk
job.batch "rook-ceph-osd-prepare-ocs-deviceset-1-data-1-jv2qk" deleted
$ oc delete -n openshift-storage job rook-ceph-osd-prepare-ocs-deviceset-0-data-1-q72z4
job.batch "rook-ceph-osd-prepare-ocs-deviceset-0-data-1-q72z4" deleted
~~~

### Remove Persistent Volume Claims

List all PVCs created for the OSDs in the cluster.

~~~
$ oc get pvc -n openshift-storage| grep deviceset
ocs-deviceset-0-data-0-hwzhx   Bound    pvc-10930547-e0d0-47cf-ba56-d68dbe59d33c   2Ti        RWO            gp2                           165m
ocs-deviceset-0-data-1-q72z4   Bound    pvc-36e0a5f7-9ef3-49e6-99d5-68c791870e61   2Ti        RWO            gp2                           162m
ocs-deviceset-1-data-0-bmpzj   Bound    pvc-fe3806cc-92f9-4382-8dad-026edae39906   2Ti        RWO            gp2                           165m
ocs-deviceset-1-data-1-jv2qk   Bound    pvc-fbd93d58-eb56-4ac1-b987-91a3983b9e00   2Ti        RWO            gp2                           162m
ocs-deviceset-2-data-0-d6tch   Bound    pvc-f523ea66-6c0b-4c00-b618-a66129af563b   2Ti        RWO            gp2                           165m
ocs-deviceset-2-data-1-r7dwg   Bound    pvc-e100bbf6-426d-4f10-af83-83b92181fb41   2Ti        RWO            gp2                           162m
~~~

Then delete only the PVCs corresponding to the OSDs we have removed.

~~~
$ oc delete -n openshift-storage pvc ocs-deviceset-2-data-1-r7dwg
persistentvolumeclaim "ocs-deviceset-2-data-1-r7dwg" deleted
$ oc delete -n openshift-storage pvc ocs-deviceset-1-data-1-jv2qk
persistentvolumeclaim "ocs-deviceset-1-data-1-jv2qk" deleted
$ oc delete -n openshift-storage pvc ocs-deviceset-0-data-1-q72z4
persistentvolumeclaim "ocs-deviceset-0-data-1-q72z4" deleted
~~~

### Final Cleanup
Verify the physical volumes that were dynamically provisioned for the OSDs we removed have been deleted.

~~~
$ oc get pvc -n openshift-storage| grep deviceset
ocs-deviceset-0-data-0-hwzhx   Bound    pvc-10930547-e0d0-47cf-ba56-d68dbe59d33c   2Ti        RWO            gp2                           169m
ocs-deviceset-1-data-0-bmpzj   Bound    pvc-fe3806cc-92f9-4382-8dad-026edae39906   2Ti        RWO            gp2                           169m
ocs-deviceset-2-data-0-d6tch   Bound    pvc-f523ea66-6c0b-4c00-b618-a66129af563b   2Ti        RWO            gp2                           169m
$ oc get pv | grep deviceset | awk '{ print ($1,$2,$6,$7) }'
pvc-10930547-e0d0-47cf-ba56-d68dbe59d33c 2Ti openshift-storage/ocs-deviceset-0-data-0-hwzhx gp2
pvc-f523ea66-6c0b-4c00-b618-a66129af563b 2Ti openshift-storage/ocs-deviceset-2-data-0-d6tch gp2
pvc-fe3806cc-92f9-4382-8dad-026edae39906 2Ti openshift-storage/ocs-deviceset-1-data-0-bmpzj gp2
~~~

Delete the OSD removal jobs.

~~~
$ oc get job -n openshift-storage | grep removal
ocs-osd-removal-3                                    1/1           6s         96m
ocs-osd-removal-4                                    1/1           6s         99m
ocs-osd-removal-5                                    1/1           7s         105m
$ for i in 5 4 3; do oc delete -n openshift-storage job ocs-osd-removal-${i}; done
job.batch "ocs-osd-removal-5" deleted
job.batch "ocs-osd-removal-4" deleted
job.batch "ocs-osd-removal-3" deleted
~~~

**Note:** Adapt the `for` loop arguments to match your OSD ids.

Verify no unnecessary pod was leftover (osd-prepare job, rook-ceph-osd pod, osd-removal job, ...).

~~~
$ oc get pods -n openshift-storage
NAME                                                              READY   STATUS      RESTARTS   AGE
csi-cephfsplugin-chl65                                            3/3     Running     0          3h1m
csi-cephfsplugin-dlp66                                            3/3     Running     0          3h1m
csi-cephfsplugin-provisioner-6bc8b8cdd9-9ngpk                     5/5     Running     0          3h1m
csi-cephfsplugin-provisioner-6bc8b8cdd9-lb26q                     5/5     Running     0          3h1m
csi-cephfsplugin-vknsv                                            3/3     Running     0          3h1m
csi-rbdplugin-7lkxd                                               3/3     Running     0          3h1m
csi-rbdplugin-pqllf                                               3/3     Running     0          3h1m
csi-rbdplugin-provisioner-6b9f9f5bf-6fpsq                         5/5     Running     0          3h1m
csi-rbdplugin-provisioner-6b9f9f5bf-zrq6f                         5/5     Running     0          3h1m
csi-rbdplugin-tdt7z                                               3/3     Running     0          3h1m
noobaa-core-0                                                     1/1     Running     0          178m
noobaa-db-0                                                       1/1     Running     0          178m
noobaa-endpoint-5dbcd54d4f-f74h7                                  1/1     Running     0          176m
noobaa-operator-6c57586b78-48j4r                                  1/1     Running     0          3h2m
ocs-operator-748d9d4469-hhhwk                                     1/1     Running     0          3h2m
rook-ceph-crashcollector-ip-10-0-129-185-c647fffb5-47r5n          1/1     Running     0          179m
rook-ceph-crashcollector-ip-10-0-187-112-b7bddbdc7-69wqv          1/1     Running     0          179m
rook-ceph-crashcollector-ip-10-0-207-213-6f5f89698-k2crd          1/1     Running     0          3h
rook-ceph-drain-canary-638c3cea6f3692016381c125ab06a1e5-bdmbjvg   1/1     Running     0          178m
rook-ceph-drain-canary-8fa99b779e22a9c5b3fe8f57e15a6416-5d94pfg   1/1     Running     0          178m
rook-ceph-drain-canary-de7548f9e9ade4c10e0196400c94bc96-692vxxd   1/1     Running     0          178m
rook-ceph-mds-ocs-storagecluster-cephfilesystem-a-d896d595q8zpd   1/1     Running     0          178m
rook-ceph-mds-ocs-storagecluster-cephfilesystem-b-7d4594f45zdk7   1/1     Running     0          178m
rook-ceph-mgr-a-64fb7ff7c7-d7pzl                                  1/1     Running     0          179m
rook-ceph-mon-a-7754ccb656-t9zmh                                  1/1     Running     0          3h
rook-ceph-mon-b-6c6f9ccfd-cwbrl                                   1/1     Running     0          179m
rook-ceph-mon-c-86b75675f4-zfrnz                                  1/1     Running     0          179m
rook-ceph-operator-f44596d6-lh4zq                                 1/1     Running     0          3h2m
rook-ceph-osd-0-7947c4f995-l4bx4                                  1/1     Running     0          178m
rook-ceph-osd-1-7cd6dc86c8-484bw                                  1/1     Running     0          178m
rook-ceph-osd-2-6b7659dd58-h5lp7                                  1/1     Running     0          178m
rook-ceph-osd-prepare-ocs-deviceset-0-data-0-hwzhx-577f8          0/1     Completed   0          179m
rook-ceph-osd-prepare-ocs-deviceset-1-data-0-bmpzj-27t5s          0/1     Completed   0          179m
rook-ceph-osd-prepare-ocs-deviceset-2-data-0-d6tch-ld7sd          0/1     Completed   0          179m
rook-ceph-tools-65fcc8988c-nw8r5                                  1/1     Running     0          171m
~~~

### Cluster Re-Expansion Example
You can easily expand the capacity of an existing cluster via the CLI through the update of the `storageDeviceSets` count in the `storagecluster` object in the `openshift-storage` namespace.

As an example, let's expand the same OCS cluster we just downsized to 3 OSDs and bring it back to its original size (6 OSDs).

~~~
$ newset=2
$ oc patch storagecluster ocs-storagecluster -n openshift-storage --type json --patch "[{ "op": "replace", "path": "/spec/storageDeviceSets/0/count", "value": ${newset} }]"
storagecluster.ocs.openshift.io/ocs-storagecluster patched
$ oc get storagecluster -n openshift-storage -o json | jq '.items[0].spec.storageDeviceSets[0].count'
2
$ oc get pods -n openshift-storage | grep osd
rook-ceph-osd-0-7947c4f995-l4bx4                                  1/1     Running     0          3h3m
rook-ceph-osd-1-7cd6dc86c8-484bw                                  1/1     Running     0          3h3m
rook-ceph-osd-2-6b7659dd58-h5lp7                                  1/1     Running     0          3h3m
rook-ceph-osd-3-5967bdf767-2ffcr                                  1/1     Running     0          50s
rook-ceph-osd-4-f7dcc6c7f-zd6tx                                   1/1     Running     0          48s
rook-ceph-osd-5-99885889b-z8x95                                   1/1     Running     0          46s
rook-ceph-osd-prepare-ocs-deviceset-0-data-0-hwzhx-577f8          0/1     Completed   0          3h4m
rook-ceph-osd-prepare-ocs-deviceset-0-data-1-hwwr7-ntm4w          0/1     Completed   0          78s
rook-ceph-osd-prepare-ocs-deviceset-1-data-0-bmpzj-27t5s          0/1     Completed   0          3h4m
rook-ceph-osd-prepare-ocs-deviceset-1-data-1-zdttb-mb5fx          0/1     Completed   0          77s
rook-ceph-osd-prepare-ocs-deviceset-2-data-0-d6tch-ld7sd          0/1     Completed   0          3h4m
rook-ceph-osd-prepare-ocs-deviceset-2-data-1-s469h-kjgdf          0/1     Completed   0          75s
$ oc get pvc -n openshift-storage
NAME                           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS                  AGE
db-noobaa-db-0                 Bound    pvc-a45d2583-9ec1-4640-b2c9-8cb0d24be7f4   50Gi       RWO            ocs-storagecluster-ceph-rbd   3h4m
ocs-deviceset-0-data-0-hwzhx   Bound    pvc-10930547-e0d0-47cf-ba56-d68dbe59d33c   2Ti        RWO            gp2                           3h4m
ocs-deviceset-0-data-1-hwwr7   Bound    pvc-db64ec09-81c7-4e53-b91d-f089607a4824   2Ti        RWO            gp2                           101s
ocs-deviceset-1-data-0-bmpzj   Bound    pvc-fe3806cc-92f9-4382-8dad-026edae39906   2Ti        RWO            gp2                           3h4m
ocs-deviceset-1-data-1-zdttb   Bound    pvc-21243378-5c7a-4df8-8605-d49559a4b01b   2Ti        RWO            gp2                           100s
ocs-deviceset-2-data-0-d6tch   Bound    pvc-f523ea66-6c0b-4c00-b618-a66129af563b   2Ti        RWO            gp2                           3h4m
ocs-deviceset-2-data-1-s469h   Bound    pvc-64a6d4db-ce5c-4a5c-87b2-3bcde59c902f   2Ti        RWO            gp2                           98s
rook-ceph-mon-a                Bound    pvc-d4977e7f-8770-45de-bc12-9c213e3d0766   10Gi       RWO            gp2                           3h6m
rook-ceph-mon-b                Bound    pvc-2df867fc-38ff-4cb1-93fd-b3281f6c5fa2   10Gi       RWO            gp2                           3h6m
rook-ceph-mon-c                Bound    pvc-b70f812e-7d02-451c-a3fb-66b438a2304b   10Gi       RWO            gp2                           3h6m
$ oc exec -n openshift-storage ${TOOLS_POD} -- ceph osd stat
6 osds: 6 up (since 75s), 6 in (since 75s); epoch: e161
$ oc exec -n openshift-storage ${TOOLS_POD} -- ceph health
HEALTH_OK
~~~

**Et voilà!**
