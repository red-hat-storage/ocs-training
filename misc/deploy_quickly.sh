#!/bin/bash

# Stop on first error
set -e

CLUSTERID=$(oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].metadata.labels.machine\.openshift\.io/cluster-api-cluster}')

curl -s https://raw.githubusercontent.com/red-hat-storage/ocs-training/master/misc/workerocs-machines.yaml | sed "s/cluster-28cf-t22gs/$CLUSTERID/g" | oc apply -f -
# cat workerocs-machines.yaml | sed "s/cluster-28cf-t22gs/$CLUSTERID/g" | oc apply -f -

oc apply -f https://raw.githubusercontent.com/openshift/ocs-operator/release-4.2/deploy/deploy-with-olm.yaml

# Wait until we have three machinesets - each with one availableReplica
# Ignore errors temporarily
echo "Waiting on OCS workers to become available"
set +e
until [[ $(oc get machinesets -n openshift-machine-api -l machine.openshift.io/cluster-api-machine-type=workerocs -o jsonpath='{.items[*].status.availableReplicas}') = "1 1 1" ]]
 do
 echo -n "."
 sleep 5
done
set -e
echo "Worker OCS machines are ready now"

# Create the OCS cluster
curl -s https://raw.githubusercontent.com/openshift/ocs-operator/release-4.2/deploy/crds/ocs_v1_storagecluster_cr.yaml | sed 's/name: example-storagecluster/name: ocs-storagecluster/g' | oc apply -f -
# Create the Ceph toolbox
curl -s https://raw.githubusercontent.com/rook/rook/release-1.1/cluster/examples/kubernetes/ceph/toolbox.yaml | sed 's/namespace: rook-ceph/namespace: openshift-storage/g'| oc apply -f -

# Wait for tools pod to be ready
oc wait -n openshift-storage -l app=rook-ceph-tools po --for=condition=Ready --timeout=5m

# Waiting for MON Pods
echo "Waiting for all three MON Pods to appear"
until [[ $(kubectl get pods -l app=rook-ceph-mon -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') = "True True True" ]];
 do
 echo -n "."
 sleep 5
done
