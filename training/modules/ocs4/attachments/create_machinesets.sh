#!/bin/bash

##Check if we have jq
if ! command -v jq &> /dev/null
then
    echo "jq could not be found"
    exit
fi

## Create Machineset from previous template just modifiying the instance type
for MACHINESET in $(oc get -n openshift-machine-api machinesets -o name | grep -v ocs )
do
  oc get -n openshift-machine-api "$MACHINESET" -o json | jq '
      del( .metadata.uid, .metadata.managedFields, .metadata.selfLink, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.generation, .status) | 
      (.metadata.name, .spec.selector.matchLabels["machine.openshift.io/cluster-api-machineset"], .spec.template.metadata.labels["machine.openshift.io/cluster-api-machineset"]) |= sub("worker";"workerocs") | 
      (.spec.template.spec.providerSpec.value.instanceType) |= "m5.4xlarge" |
      (.spec.template.spec.metadata.labels["cluster.ocs.openshift.io/openshift-storage"]) |= ""' | oc apply -f -
done

## If using a RHPDS env with single AZ, create 3 replicas in same AZ.
if [ $(oc get -n openshift-machine-api machinesets -o name | grep ocs | wc -l) -eq 1 ]
then
   OCS_MACHINESET=$(oc get -n openshift-machine-api machinesets -o name | grep ocs)
   oc scale -n openshift-machine-api "$OCS_MACHINESET" --replicas=3
fi
