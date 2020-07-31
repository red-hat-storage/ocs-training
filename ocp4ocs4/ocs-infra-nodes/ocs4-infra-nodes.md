# Background

The Machine API cannot facilitate the creation of nodes that have a single node-role `node-role.kubernetes.io/infra`. Nodes created with the Machine API can only have node-roles in addition to `node-role.kubernetes.io/worker`. A common approach is desirable for consistency across environemnts, both those with and without Machine API support. As such we suggest the creation of nodes with dual worker/infra node-roles

Once the Machine API supports the creation of nodes without the `node-role.kubernetes.io/worker` node-role, probaly in conjunction with a infrastructure node specific MachineConfig, then we can move to suggesting single node-role infra nodes.

# Anatomy of a Infrastructure node.

* Label `node-role.kubernetes.io/infra` to node object
* Tainted to repel customer applications / workloads
* Taint key/value matching OCS toleration

Example from labeling and taint required for infrastructure node that will be used to run OCS services:
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

If the Machine API is supported in the environment, then labels should be added to the templates for the Machine Sets that will be provisioning the infrastructure nodes. Avoid the anti-pattern of adding labels manully to nodes created by the machine API. Doing so is analogous to adding labels to pods created by a deployment, in both cases, when (not if) the pod/node fails, it's replacement will not have the appropriate labels.

NOTE: In EC2 environments, you will want exactly three machine sets, each provisioning infrastructure nodes in a particular availability zone.

Example Machine Set template that will create nodes with appropriate labeling and taint required for infrastructure nodes that will be used to run OCS services:
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
oc label node ... 
oc taint node <node> node.ocs.openshift.io/storage="true":NoSchedule
~~~
