# OCS-training

All documents were developed for OpenShift running on AWS in the `us-east-1` region. Running them on VMWare or other clouds might be possible, but is not tested.

## Core training

These repository contains hands-on workshops for both system administrators and application developers interested in learning how to deploy and manage OpenShift Container Storage (OCS)

In [ocp4ocs4](ocp4ocs4/ocs4.adoc) you will find the new workshop that leverages the OCS operator.

In [ocp4rook](ocp4rook/ocs4.adoc) you will find the old workshop which uses upstream Rook to provision a Ceph-based storage backend. (Deprecated)

## Workloads

These folders contain Workloads that explain how to leverage OCS 4 with common applications. It is expected that the Core [ocp4ocs4](ocp4ocs4/ocs4.adoc) training has been finished before any of the below labs are tried.

* [CICD / Jenkins](ocs4jenkins/Jenkins.adoc)
* [Streaming / Kafka](ocs4kafka/Readme.adoc)
* [Metrics / Prometheus](ocs4metrics/Readme.adoc)
* [Databases / PostgreSQL](ocs4postgresql) (pending)
* [Container Image Registry / Quay](ocs4registry/registry.adoc)
* [Logging / Elasticsearch](ocs4logging) (pending)
