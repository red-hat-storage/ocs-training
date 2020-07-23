# Overview

OpenShift Container Platform 4.3 and 4.4 has been verified to work in conjunction with [local storage](https://docs.openshift.com/container-platform/4.3/storage/persistent_storage/persistent-storage-local.html) devices and OpenShift Container Storage 4.4 on AWS EC2, VMware, and Bare Metal hosts.

# Installing the Local Storage Operator

First, you will need to create a namespace for the Local Storage Operator. A self descriptive 'local-storage' namespace is recommended. 

```
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: local-storage
spec: {}
EOF
```

Next, you will need to install the Local Storage Operator. This can be done via the following commands, or through the OpenShift Console. If you choose to install the Local Storage Operator from the OpenShift Console, ensure that you install it into the `local-storage` namespace you created in the previous step.

Create Operator Group for Local Storage Operator:
```
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  annotations:
    olm.providedAPIs: LocalVolume.v1.local.storage.openshift.io
  name: local-storage
  namespace: local-storage
spec:
  targetNamespaces:
  - local-storage
EOF
```

Subscribe to Local Storage Operator:
```
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: local-storage-operator
  namespace: local-storage 
spec:
  channel: "4.5"
  installPlanApproval: Automatic
  name: local-storage-operator 
  source: redhat-operators 
  sourceNamespace: openshift-marketplace
EOF
```

## Preparing Nodes

You will need to add the OCS label to each OCP node. The OCS operator looks for this label to know which nodes can be scheduling targets for OCS components. Later we will configure the Local Storage Operator to create PVs from storage devices on nodes with this label. You must have a minimum of three labeled worker nodes. To label the nodes use the following command:

```
oc label node <NodeName> cluster.ocs.openshift.io/openshift-storage=''
```
## Finding Device Names 
Next, you will need to know the device names on the nodes labeled for OCS. You can access the nodes using `oc debug node` and issuing the `lsblk` command after `chroot`.

```
$ oc debug node/<node_name>

sh-4.4# chroot /host
sh-4.4# lsblk
NAME                         MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
nvme0n1                      259:0    0   120G  0 disk
|-nvme0n1p1                  259:1    0   384M  0 part /boot
|-nvme0n1p2                  259:2    0   127M  0 part /boot/efi
|-nvme0n1p3                  259:3    0     1M  0 part
`-nvme0n1p4                  259:4    0 119.5G  0 part
  `-coreos-luks-root-nocrypt 253:0    0 119.5G  0 dm   /sysroot
nvme1n1                      259:5    0  1000G  0 disk
nvme2n1                      259:6    0  1000G  0 disk
```
After you know which local devices are available, in this case nvme0n1 and nvme1n1, you can now find the by-id, a unique name depending on the hardware serial number for each device.

```
sh-4.4# ls -l /dev/disk/by-id/
total 0
lrwxrwxrwx. 1 root root 10 Mar 17 16:24 dm-name-coreos-luks-root-nocrypt -> ../../dm-0
lrwxrwxrwx. 1 root root 13 Mar 17 16:24 nvme-Amazon_EC2_NVMe_Instance_Storage_AWS10382E5D7441494EC -> ../../nvme0n1
lrwxrwxrwx. 1 root root 13 Mar 17 16:24 nvme-Amazon_EC2_NVMe_Instance_Storage_AWS60382E5D7441494EC -> ../../nvme1n1
lrwxrwxrwx. 1 root root 13 Mar 17 16:24 nvme-nvme.1d0f-4157533130333832453544373434313439344543-416d617a6f6e20454332204e564d6520496e7374616e63652053746f72616765-00000001 -> ../../nvme0n1
lrwxrwxrwx. 1 root root 13 Mar 17 16:24 nvme-nvme.1d0f-4157533630333832453544373434313439344543-416d617a6f6e20454332204e564d6520496e7374616e63652053746f72616765-00000001 -> ../../nvme1n1
```

Article that has utility for gathering /dev/disk/by-id for all OCP nodes with OCS label (cluster.ocs.openshift.io/openshift-storage='') https://access.redhat.com/solutions/4928841.

## Create LSO CR for OSD PVs

The device paths you provide for the OSDs PVs *can only be raw block devices*. This is due to the fact that the operator creates distinct partitions on the provided raw block devices for the OSD metadata and OSD data. The example is for one storage device on each of 3 OCP nodes with the OCS label. Use this command to verify that your OCP nodes do have an OCS label.

```
oc get nodes -l cluster.ocs.openshift.io/openshift-storage=
```

```
apiVersion: local.storage.openshift.io/v1
kind: LocalVolume
metadata:
  name: local-block
  namespace: local-storage
spec:
  nodeSelector:
    nodeSelectorTerms:
    - matchExpressions:
        - key: cluster.ocs.openshift.io/openshift-storage
          operator: In
          values:
          - ""
  storageClassDevices:
    - storageClassName: localblock
      volumeMode: Block
      devicePaths:
        - /dev/disk/by-id/nvme-Amazon_EC2_NVMe_Instance_Storage_AWS10382E5D7441494EC   # <-- modify this line
        - /dev/disk/by-id/nvme-Amazon_EC2_NVMe_Instance_Storage_AWS1F45C01D7E84FE3E9   # <-- modify this line
        - /dev/disk/by-id/nvme-Amazon_EC2_NVMe_Instance_Storage_AWS136BC945B4ECB9AE4   # <-- modify this line
```

```
oc create -f block-storage.yaml
```

# Installing OpenShift Container Storage
Verify that the community-operators catalogsource is created (oc get catalogsource -n openshift-marketplace). If it is not present, then create this custom catalogsource for lib-bucket-provisioner operator before attempting to install OCS.

```
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: lib-bucket-catalogsource
  namespace: openshift-marketplace
spec:
  displayName: lib-bucket-provisioner
  icon:
    base64data: PHN2ZyBpZD0iTGF5ZXJfMSIgZGF0YS1uYW1lPSJMYXllciAxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxOTIgMTQ1Ij48ZGVmcz48c3R5bGU+LmNscy0xe2ZpbGw6I2UwMDt9PC9zdHlsZT48L2RlZnM+PHRpdGxlPlJlZEhhdC1Mb2dvLUhhdC1Db2xvcjwvdGl0bGU+PHBhdGggZD0iTTE1Ny43Nyw2Mi42MWExNCwxNCwwLDAsMSwuMzEsMy40MmMwLDE0Ljg4LTE4LjEsMTcuNDYtMzAuNjEsMTcuNDZDNzguODMsODMuNDksNDIuNTMsNTMuMjYsNDIuNTMsNDRhNi40Myw2LjQzLDAsMCwxLC4yMi0xLjk0bC0zLjY2LDkuMDZhMTguNDUsMTguNDUsMCwwLDAtMS41MSw3LjMzYzAsMTguMTEsNDEsNDUuNDgsODcuNzQsNDUuNDgsMjAuNjksMCwzNi40My03Ljc2LDM2LjQzLTIxLjc3LDAtMS4wOCwwLTEuOTQtMS43My0xMC4xM1oiLz48cGF0aCBjbGFzcz0iY2xzLTEiIGQ9Ik0xMjcuNDcsODMuNDljMTIuNTEsMCwzMC42MS0yLjU4LDMwLjYxLTE3LjQ2YTE0LDE0LDAsMCwwLS4zMS0zLjQybC03LjQ1LTMyLjM2Yy0xLjcyLTcuMTItMy4yMy0xMC4zNS0xNS43My0xNi42QzEyNC44OSw4LjY5LDEwMy43Ni41LDk3LjUxLjUsOTEuNjkuNSw5MCw4LDgzLjA2LDhjLTYuNjgsMC0xMS42NC01LjYtMTcuODktNS42LTYsMC05LjkxLDQuMDktMTIuOTMsMTIuNSwwLDAtOC40MSwyMy43Mi05LjQ5LDI3LjE2QTYuNDMsNi40MywwLDAsMCw0Mi41Myw0NGMwLDkuMjIsMzYuMywzOS40NSw4NC45NCwzOS40NU0xNjAsNzIuMDdjMS43Myw4LjE5LDEuNzMsOS4wNSwxLjczLDEwLjEzLDAsMTQtMTUuNzQsMjEuNzctMzYuNDMsMjEuNzdDNzguNTQsMTA0LDM3LjU4LDc2LjYsMzcuNTgsNTguNDlhMTguNDUsMTguNDUsMCwwLDEsMS41MS03LjMzQzIyLjI3LDUyLC41LDU1LC41LDc0LjIyYzAsMzEuNDgsNzQuNTksNzAuMjgsMTMzLjY1LDcwLjI4LDQ1LjI4LDAsNTYuNy0yMC40OCw1Ni43LTM2LjY1LDAtMTIuNzItMTEtMjcuMTYtMzAuODMtMzUuNzgiLz48L3N2Zz4=
    mediatype: image/svg+xml
  image: quay.io/noobaa/lib-bucket-catalog@sha256:b9c9431735cf34017b4ecb2b334c3956b2a2322ce31ac88b29b1e4faf6c7fe7d
  publisher: Red Hat
  sourceType: grpc
  ```
  
## Install Operator

Create `openshift-storage` namespace
```
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: openshift-storage
spec: {}
EOF
```

Create Operator Group for OCS Operator
```
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-storage-operatorgroup
  namespace: openshift-storage
spec:
  targetNamespaces:
  - openshift-storage
EOF
```

Subscribe to OCS Operator
```
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ocs-operator
  namespace: openshift-storage 
spec:
  channel: "stable-4.4"
  installPlanApproval: Automatic
  name: ocs-operator 
  source: redhat-operators 
  sourceNamespace: openshift-marketplace
EOF
```

NOTE:
Prior to OCS 4.5 for OCP disconnected environments, the lib-bucket-provisioner csv and deployment will need to be edited and the image quay.io/noobaa/pause will need to be replaced with quay.io/noobaa/pause@sha256:b31bfb4d0213f254d361e0079deaaebefa4f82ba7aa76ef82e90b4935ad5b105. Edit the lib-bucket-provisioner csv first with this image@sha. Next, edit the lib-bucket-provisioner deployment and replace quay.io/noobaa/pause with this image@sha if not already correct.

## Create Cluster

Storage Cluster CR

```
apiVersion: ocs.openshift.io/v1
kind: StorageCluster
metadata:
  name: ocs-storagecluster
  namespace: openshift-storage
spec:
  manageNodes: false
  monDataDirHostPath: /var/lib/rook
  storageDeviceSets:
  - count: 1   # <-- modify count to to desired value
    dataPVCTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 1
        storageClassName: localblock
        volumeMode: Block
    name: ocs-deviceset
    placement: {}
    portable: false
    replica: 3
    resources: {}
```

```
oc create -f storagecluster.yaml
```

# Verifying the Installation

Deploy the Rook-Ceph toolbox pod

```
oc patch OCSInitialization ocsinit -n openshift-storage --type json --patch  '[{ "op": "replace", "path": "/spec/enableCephTools", "value": true }]'
```

Establish a remote shell to the toolbox pod

```
TOOLS_POD=$(oc get pods -n openshift-storage -l app=rook-ceph-tools -o name)
oc rsh -n openshift-storage $TOOLS_POD
```

Run `ceph status` and `ceph osd tree` to see that status of the Ceph cluster

```
sh-4.4# ceph status
```

```
sh-4.4# ceph osd tree
```

## Create test application using CephRBD PVC

```
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rbd-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: ocs-storagecluster-ceph-rbd
EOF
```
Validate new PVC is created.

```
oc get pvc | grep rbd-pvc
```

```
cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: csirbd-demo-pod
spec:
  containers:
   - name: web-server
     image: nginx
     volumeMounts:
       - name: mypvc
         mountPath: /var/lib/www/html
  volumes:
   - name: mypvc
     persistentVolumeClaim:
       claimName: rbd-pvc
       readOnly: false
EOF
```

Validate new Pod is using CephRBD PVC.

```
oc get pod csirbd-demo-pod -o yaml| grep "claimName: rbd-pvc"
```

## Upgrade OCS version (major version) 

Validate current version of OCS.

```
oc get csv -n openshift-storage
``` 

Example output
```
NAME                            DISPLAY                       VERSION   REPLACES   PHASE
lib-bucket-provisioner.v1.0.0   lib-bucket-provisioner        1.0.0                Succeeded
ocs-operator.v4.3.0             OpenShift Container Storage   4.3.0                Succeeded
```

Verify there is a new OCS stable channel.

```
oc describe packagemanifests ocs -n openshift-marketplace |grep stable-
``` 

Example output
```
    Name:         stable-4.2
    Name:         stable-4.3
    Name:           stable-4.4
  Default Channel:  stable-4.4
```  
  
Apply subscription with new stable-4.4 channel.

```
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ocs-operator
  namespace: openshift-storage 
spec:
  channel: "stable-4.4"
  installPlanApproval: Automatic
  name: ocs-operator 
  source: redhat-operators 
  sourceNamespace: openshift-marketplace
EOF
```

Validate subscription is updating

```
watch oc get csv -n openshift-storage
``` 

Example output
```
NAME                            DISPLAY                       VERSION   REPLACES              PHASE
lib-bucket-provisioner.v1.0.0   lib-bucket-provisioner        1.0.0                           Succeeded
ocs-operator.v4.3.0             OpenShift Container Storage   4.3.0                           Replacing
ocs-operator.v4.4.0             OpenShift Container Storage   4.4.0     ocs-operator.v4.3.0   Installing
```

Validate that all pods in openshift-storage are eventually in a running state after updating. Also verify that Ceph is healthy using instructions in prior section.
