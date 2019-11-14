# OCS-training

All activites were developed for OpenShift Container Platform (OCP 4) running on AWS in the `us-east-1` region. Running these activitesm on OCP 4.x on VMWare or other clouds should be possible, but is not tested.

## Core training

These repository contains hands-on workshops for both system administrators and application developers interested in learning how to deploy and manage OpenShift Container Storage (OCS)

In [ocp4ocs4](ocp4ocs4/ocs4.adoc) you will find the new workshop that leverages the OCS 4 operator.

In [ocp4rook](ocp4rook/ocs4.adoc) you will find the prior workshop which uses upstream Rook v1.0 to provision a Ceph-based storage backend. (Deprecated)

## Workloads

These folders contain OCP Workloads that explain how to leverage OCS 4 with common these applications. It is expected that the Core [ocp4ocs4](ocp4ocs4/ocs4.adoc) training has been finished before any of the below labs are tried. The first 3 Workloads are important for using OCS 4 to back OCP 4 infrastructure.

* [OCP Container Image Registry](ocs4registry/registry.adoc)
* [OCP Metrics / Prometheus](ocs4metrics/Readme.adoc)
* [OCP Logging / Elasticsearch](ocs4logging/Readme.adoc)
* [CICD / Jenkins](ocs4jenkins/Jenkins.adoc)
* [Streaming / Kafka](ocs4kafka/Readme.adoc)
* [Databases / PostgreSQL](ocs4postgresql/PostgreSQL.adoc)
