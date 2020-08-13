# Background

The Machine API cannot facilitate the creation of nodes that have a single node-role `node-role.kubernetes.io/infra`. Nodes created with the Machine API can only have node-roles in addition to `node-role.kubernetes.io/worker`. A common approach is desirable for consistency across environemnts, both those with and without Machine API support. As such we suggest the creation of nodes with dual worker/infra node-roles

If the Machine API eventually supports the creation of nodes without the `node-role.kubernetes.io/worker` node-role, then we could instead suggest single node-role infrasturcture nodes. Without a `node-role.kubernetes.io/worker` node-role, a MachineCOnfigPool needs to be created to facilitate node upgrades.

# Anatomy of a Infrastructure node.

Infrastructure nodes have a few attributes, notably they are:

* Labeled with `node-role.kubernetes.io/infra`
* Tainted with `node.ocs.openshift.io/storage="true"`

The label identifies the nodes infra nodes, and the taint repels customer applications / workloads.

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

# Machine sets

If the Machine API is supported in the environment, then labels should be added to the templates for the Machine Sets that will be provisioning the infrastructure nodes. Avoid the anti-pattern of adding labels manually to nodes created by the machine API. Doing so is analogous to adding labels to pods created by a deployment, in both cases, when (not if) the pod/node fails, it's replacement will not have the appropriate labels.

NOTE: In EC2 environments, you will want exactly three machine sets, each configured to provision infrastructure nodes in a distinct availability zone.

Example Machine Set template that creates nodes with the appropriate taint and lables required for infrastructure nodes that will be used to run OCS services:
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

# Manual addition

Only when the Machine APi is not supported in the environment should labels be directly applied to nodes. 

~~~
oc label node <node> node-role.kubernetes.io/infra=""
oc label node <node> cluster.ocs.openshift.io/openshift-storage=""
oc taint node <node> node.ocs.openshift.io/storage="true":NoSchedule
~~~
