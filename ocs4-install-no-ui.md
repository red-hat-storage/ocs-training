# Overview

OpenShift Container Platform 4.3 has been verified to work in conjunction with [local storage](https://docs.openshift.com/container-platform/4.3/storage/persistent_storage/persistent-storage-local.html) devices and OpenShift Container Storage 4.3 on AWS EC2, VMware, KVM guests, and Bare Metal hosts.

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
  channel: "4.4"
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
  channel: "stable-4.3"
  installPlanApproval: Automatic
  name: ocs-operator 
  source: redhat-operators 
  sourceNamespace: openshift-marketplace
EOF
```

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
# ceph status
```

```
# ceph osd tree
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
