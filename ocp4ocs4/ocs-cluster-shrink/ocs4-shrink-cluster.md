# OpenShift Container Storage (OCS) 4.5 Shrink Existing Internal Cluster
This document is to supplement the OpenShift Container Storage (OCS) and provide
instructions for shrinking a previously deployed internal mode cluster.
It is not clear at this point when this procedure will be officially documented
nor when it will be automated via the `rook-ceph` operator.

This document currently details the step for a dynamically provisioned OCS cluster
through the `gp2` (AWS) or `thin` storage class regardless of the OSD device size.

This is a live document to be used in various environments and configurations.
If you find any mistakes or missing instructions, please add an [Issue][8] or
contact Annette Clewett (aclewett@redhat.com) and JC Lopez (jelopez@redhat.com)
via email.

## Overview
Red Hat Ceph Storage offers the ability to safely shrink an existing cluster by
removing OSDs or MONs but this functionality is not documented for OCS. The purpose
of this document is to details the steps necessary to safely reduce the number
of OSDs in an OCS internal cluster. Such situation may be faced when an application
is migrated or removed from the cluster and the OCP administrator would like
to reduce the amount of resources used by the OCS cluster (`gp2` persistent volumes,
CPU and RAM consumed by OSDs that are no longer needed).

## Prerequisites
These requirements need to be met before proceeding.
1. An OCS 4.5 or higher internal cluster 

2. The OCS cluster is healthy and all data is protected

3. The OCS cluster contains 6 or more OSDs

## Procedure

### Identify how many devicesets have been deployed
Before you can shrink your cluster you need to identify how many devicesets have
been deployed so you can adjust the value properly. 

You may shrink your cluster one deviceset at a time. Simply loop through this procedure
for each deviceset that has to be removed from the cluster.

~~~
$ deviceset=$(oc get storagecluster -o json | jq '.items[0].spec.storageDeviceSets[0].count')
$ echo ${deviceset}
2
~~~

**Note:** If the number of storage devicesets is `1` do not proceed with this procedure as you will
end up loosing all data in your OCS cluster.

Start a Ceph toolbox pod to verify the health of your internal Ceph cluster.

~~~
$ oc patch OCSInitialization ocsinit -n openshift-storage --type json --patch  '[{ "op": "replace", "path": "/spec/enableCephTools", "value": tru
e }]'
~~~

Verify the status of your cluster.

~~~
$ TOOLS_POD=$(oc get pods -n openshift-storage -l app=rook-ceph-tools -o name)
$ oc exec -n openshift-storage $TOOLS_POD -- ceph health
HEALTH_OK
~~~

**Note:** If the status of the cluster is not HEALTH_OK please address any issue prior to proceeding.

### Decrease DeviceSet Count

~~~
$ oc patch storagecluster ocs-storagecluster -n openshift-storage --type json --patch '[{ "op": "replace", "path": "/spec/storageDeviceSets/0/count", "value": {n} }]'
~~~

Make `{n}` as the the `$deviceset - 1`. In this example `{n}` will be a value of `1`.

~~~
$ oc patch storagecluster ocs-storagecluster -n openshift-storage --type json --patch '[{ "op": "replace", "path": "/spec/storageDeviceSets/0/count", "value": 1 }]'
storagecluster.ocs.openshift.io/ocs-storagecluster patched
~~~

Verify the storagecluster object has been updated.

~~~
$ oc get storagecluster -n openshift-storage -o json | jq '.items[0].spec.storageDeviceSets[0].count'
1
~~~
