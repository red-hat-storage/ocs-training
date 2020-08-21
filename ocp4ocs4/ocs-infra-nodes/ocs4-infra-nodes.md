# Why use Infrastructure nodes?
Using Infrastructure nodes to schedule OpenShift Container Storage (OCS) resources will save on OpenShift Container Platform (OCP) subscription costs. Any OCP node that has a `infra` node-role label will only require OCS subscription but no OCP subscription.
# Background
Currently the Machine API cannot handle the creation of nodes carrying only the `node-role.kubernetes.io/infra` node-role label. Nodes created with the Machine API can only have node-roles added along with the default `node-role.kubernetes.io/worker`. 

A common approach is desirable for consistency across environments, both those with and without Machine API support (reference section below for manual configuration of `infa` nodes). Because of this, it highly recommended in all cases to have nodes with the dual `worker/infra` node-role or label.
# Anatomy of an Infrastructure node
Infrastructure nodes for use with OCS have a few attributes. Required is the `infra` label so that the OCP subscription cost will not be applied to the new `infra` node.

* Labeled with `node-role.kubernetes.io/infra`

Adding a NoSchedule OCS taint is also required so that the `infra` node will only schedule OCS resources. 

* Tainted with `node.ocs.openshift.io/storage="true"`

The label identifies the OCP node as a `infra` node so that OCP subscription cost is not applied. The taint prevents non-OCS resources to be scheduled on the tainted nodes. If using local storage devices for OCS then a toleration will need to be added to allow `Local Storage Operator` (LSO) resources to schedule on the `infra` nodes. Reference section below for how this is done.

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
Only when the Machine APi is not supported in the environment should labels be directly applied to nodes. Manual creation will require that at least 3 OCP worker nodes are available to schedule OCS services and that these nodes have sufficient CPU and memory resources. To avoid the OCP subscription cost the following is required:

~~~
oc label node <node> node-role.kubernetes.io/infra=""
oc label node <node> cluster.ocs.openshift.io/openshift-storage=""
~~~

Adding a NoSchedule OCS taint is also required so that the `infra` node will only schedule OCS resources and repel any other non-OCS workloads.

~~~
oc adm taint <node> node.ocs.openshift.io/storage="true":NoSchedule
~~~

It is highly recommended to keep the `worker` node-role on the new `infra` node. Currently OCP default is to *only* create a worker and master `MachineConfigPool` used for applying any new `MachineConfig` including upgrading OCP. If the `worker` node-role is removed from a OCP node the changes in the new `MachineConfig` will not be applied to nodes with *only* the `infra` node-role.
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
		
