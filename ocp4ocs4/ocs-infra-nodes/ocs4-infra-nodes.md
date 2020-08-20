# Why use Infrastructure nodes?
Using Infrastructure nodes to schedule OpenShift Container Storage (OCS) resources will save on OpenShift Container Platform (OCP) subscription costs. Any OCP node that has a `infra` node-role label will only be counted for OCS subscription cost and will not be counted for OCP subscription cost.
# Background
Currently the Machine API cannot facilitate the creation of nodes that have a single node-role `node-role.kubernetes.io/infra`. Nodes created with the Machine API can only have node-roles in addition to `node-role.kubernetes.io/worker`. A common approach is desirable for consistency across environments, both those with and without Machine API support. As such we suggest the creation of nodes with dual worker/infra node-roles or labels.

If the Machine API eventually supports the creation of nodes without the `node-role.kubernetes.io/worker` node-role, then we could instead suggest single node-role infrasturcture nodes. Without a `node-role.kubernetes.io/worker` node-role, a MachineCOnfigPool needs to be created to facilitate node upgrades or any MachineConfig changes.
# Anatomy of an Infrastructure node
Infrastructure nodes for use with OpenShift Container Storage (OCS) have a few attributes. Required is the `infra` label:

* Labeled with `node-role.kubernetes.io/infra`

Adding a NoSchedule OCS taint is highly recommended so that the `infra` node will only schedule OCS resources. 

* Tainted with `node.ocs.openshift.io/storage="true"`

The label identifies the OCP node as a `infra` node so that OCP subscription cost is not applied. The taint repels other applications / workloads other than OCS resources. If using local storage devices for OCS then a toleration will need to be added to allow `Local Storage Operator` (LSO) resources to schedule on the `infra` nodes.

Example of the taint and labels required on infrastructure node that will be used to run OCS services:
~~~
    spec:
      taints:
      - effect: NoSchedule
        key: node.ocs.openshift.io/storage
        value: "true"
      metadata:
        creationTimestamp: null
        labels:
          node-role.kubernetes.io/worker: ""
          node-role.kubernetes.io/infra: ""
          cluster.ocs.openshift.io/openshift-storage: ""
~~~
# Machine sets for creating Infrastructure nodes
If the Machine API is supported in the environment, then labels should be added to the templates for the Machine Sets that will be provisioning the infrastructure nodes. Avoid the anti-pattern of adding labels manually to nodes created by the machine API. Doing so is analogous to adding labels to pods created by a deployment. In both cases, when the pod/node fails, the replacement pod/node will not have the appropriate labels.

NOTE: In EC2 environments, you will want three machine sets, each configured to provision infrastructure nodes in a distinct availability zone (i.e, us-east-2a, us-east-2b, us-east-2c). Currently OCS does not support deploying in more than 3 availability zones.

Example Machine Set template that creates nodes with the appropriate taint and labels required for infrastructure nodes that will be used to run OCS services:

~~~
  template:
    metadata:
      creationTimestamp: null
      labels:
        machine.openshift.io/cluster-api-cluster: kb-s25vf
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: kb-s25vf-infra-us-west-2a
    spec:
      taints:
      - effect: NoSchedule
        key: node.ocs.openshift.io/storage
        value: "true"
      metadata:
        creationTimestamp: null
        labels:
          node-role.kubernetes.io/infra: ""
          cluster.ocs.openshift.io/openshift-storage: ""
~~~
# Manual creation of Infrastructure nodes
Only when the Machine APi is not supported in the environment should labels be directly applied to nodes. 

~~~
oc label node <node> node-role.kubernetes.io/infra=""
oc label node <node> cluster.ocs.openshift.io/openshift-storage=""
oc taint node <node> node.ocs.openshift.io/storage="true":NoSchedule
~~~
# Toleration for Local Storage Operator 
When local storage devices are used for creating the OCS cluster (i.e., AWS i3en.3xlarge instance type) then LSO will need to installed before OCS can be deployed. In order to allow the LSO pods to schedule on the `infra` nodes with the OCS NoSchedule taint, a toleration has to be added to the `LocalVolume` custom resource file.

Here is an example with the toleration `node.ocs.openshift.io/storage=true` added.

~~~
apiVersion: local.storage.openshift.io/v1
kind: LocalVolume
metadata:
  name: local-block
  namespace: local-storage
  labels:
    app: ocs-storagecluster
spec:
  tolerations:
  - key: "node.ocs.openshift.io/storage"
    value: "true"
    effect: NoSchedule
  nodeSelector:
    nodeSelectorTerms:
      - matchExpressions:
          - key: cluster.ocs.openshift.io/openshift-storage
            operator: In
            values:
              - ''
  storageClassDevices:
    - storageClassName: localblock
      volumeMode: Block
      devicePaths:
        ...
~~~

This will allow LSO pods to schedule and PVs to be created from devices listed under `devicePaths:`. The recommended practice is to use /dev/disk/by-id/<ID> to identify the storage devices that will be used for OCS.		
		
