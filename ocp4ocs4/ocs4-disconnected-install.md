# OpenShift Container Storage (OCS) 4.4 Disconnected Installation - Development Preview
This document is to supplement OpenShift Container Platform (OCP) documentation for installing the OpenShift Container Storage (OCS) service in a air-gap disconnected or proxy environment. Reference official OCP documentation [here][1].

**Development Preview releases are meant for customers who are willing to evaluate new products or releases of products in a early stage of product development. In this case, OCS 4.4 `connected` is GA and supported, but OCS 4.4 `disconnected` is not yet released or supported.**

This is a live document to be used in various environments and configurations. If you find any mistakes or missing instructions, please add an [Issue][8] or contact Annette Clewett (aclewett@redhat.com) and JC Lopez (jelopez@redhat.com) via email.

## Overview
In a disconnected OpenShift environment there is no access to the OLM catalog and the Red Hat image registries. In order to install OCS you need to do 2 things:

1. Provide catalogs that contain OCS, Local Storage Operator (LSO), and lib-bucket-provisioner CSV (Cluster Service Version).
    - This can be done using the command `oc adm catalog build`. This command goes over a given catalog (e.g. redhat-operators) and builds an olm catalog image and then pushes it to the mirror registry.
    - Given `lib-bucket-provisioner` is currently a dependency for OCS installation, you will need to build a custom catalog image for this Community operator. Future versions of OCS will not need lib-bucket-provisioner.
	
	
2. Mirror all images that are required by OCS to a mirror registry running on a machine that has access to the Internet. Once the mirror registry has been updated, transfer the content of the mirror registry to a registry that can be accessed from your OCP cluster.
    - This is done using the command `oc adm catalog mirror`. This command goes over the CSVs in the catalog and copies all required images to the mirror registry.
    - To work around the missing `relatedImages` in the OCS and lib-bucket-provisioner CSV, you will need to manually mirror required images which are not copied with `oc adm catalog mirror`. This is done using `oc image mirror`.
    - The `oc adm catalog mirror` step generates the `imageContentSourcePolicy.yaml` file to install in the cluster. This resource tells OCP the external registry mapping for each image in the mirror registry. Add additional mirroring mappings for the missing `relatedImages` for OCS and lib-bucket-provisioner before applying `imageContentSourcePolicy.yaml`in the cluster.

## Prerequisites
These requirements need to be met before proceeding.
1. An OCP 4.3 or higher disconnected cluster is already installed and a mirror registry exists on a bastion host ([see here][4]).   

2. The oc client [version 4.4][5] is installed and logged into the cluster as the cluster-admin role. 

3. Export env vars (fill the correct details for your setup).
  ```
  export AUTH_FILE="<location_of_auth.json>"
  export MIRROR_REGISTRY_DNS="<registry_host_name>:<port>"
  ```
4. Create your auth file.

* The location of the auth.json file generated when you use podman or docker to login to registries using podman. The auth file is located either in your home directory under .docker or /run/user/your_uid/containers/auth.json or /var/run/containers/your_uid/auth.json.

* Get your unique redhat registry [pull secret][3] and paste it to `${AUTH_FILE}`
* Podman login to the mirror registry and store the credentials in `${AUTH_FILE}`
  ```
  podman login ${MIRROR_REGISTRY_DNS} --tls-verify=false --authfile ${AUTH_FILE}
  ```
You should eventually get something similar to this:
  ```json
  {
    "auths": {
        "cloud.openshift.com": {
            "auth": "*****************",
            "email": "user@redhat.com"
        },
        "quay.io": {
            "auth": "*****************",
            "email": "user@redhat.com"
        },
        "registry.connect.redhat.com": {
            "auth": "*****************",
            "email": "user@redhat.com"
        },
        "registry.redhat.io": {
            "auth": "*****************",
            "email": "user@redhat.com"
        },
        "<your_registry>": {
            "auth": "*****************",
        }
    }
  }
  ```

## Building and mirroring standard redhat-operator catalog image
Cluster administrators can build a custom Operator catalog image to be used by Operator Lifecycle Manager (OLM) and push the image to a container image registry that supports Docker v2-2. For a OCP cluster on a restricted network, this registry must have access to registry.access.redhat.com, registry.redhat.io and quay.io during the build and mirroring process (such as the mirror registry created during the restricted network installation).
- **Build operators catalog for redhat-operators**  
The tag of the `ose-operator-registry` in the `--from` flag should match the major and minor versions of the OCP cluster (e.g., 4.4). If this is for an update of the redhat-operators catalog make sure to change the `ose-operator-registry` tag to latest version (e.g., v4.4 -> v4.5).
  ```
  oc adm catalog build --appregistry-org redhat-operators --from=registry.redhat.io/openshift4/ose-operator-registry:v4.4 --to=${MIRROR_REGISTRY_DNS}/olm/redhat-operators:v1 --registry-config=${AUTH_FILE} --filter-by-os="linux/amd64" --insecure
  ```

- **Mirror the redhat-operators catalog**  
This is a long operation and could take 1-5 hours. It requires 60-70 GB of disk space on the bastion (the mirror machine).
  ```
  oc adm catalog mirror ${MIRROR_REGISTRY_DNS}/olm/redhat-operators:v1 ${MIRROR_REGISTRY_DNS}  --insecure --registry-config=${AUTH_FILE}
  ```

- **Disable the default OperatorSources by adding disableAllDefaultSources: true to the spec**
  ```
  oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
  ```

## Building and mirroring custom catalog image for specific operators (optional)
This method, described [here][6], is very useful for creating a custom redhat-operators catalog that only includes the operators you need to install in your OCP cluster. The instructions would replace using `oc adm catalog build` and `oc adm catalog mirror` in the previous section.

In the case of installing OCS, this would be the ocs-operator and local-storage-operator that would go in your `offline-operator-list`. Example below for entries in this file:

```
local-storage-operator
ocs-operator
```
## OCS version 4.4.0 instructions 
For OCS 4.4.0, installing in a disconnected or offline environment is a tech preview feature, hence a few more manual steps needed. Future versions of OCS should not need these additional steps to properly install.

### Mirroring missing images
  In OCS version 4.4.0 many of the `relatedImages` are detailed in the CSV, ocs-operator.v4.4.0.clusterserviceversion.yaml. Even so you still need to add a few missing images that are not yet in the OCS 4.4 CSV `relatedImages` section. Below is an example of a mapping file for OCS-4.4.0 that includes the missing images for OCS 4.4.0.

  Save content below to mapping-missing.txt:
  
  ```
registry.redhat.io/openshift4/ose-csi-external-resizer-rhel7@sha256:e7302652fe3f698f8211742d08b2dcea9d77925de458eb30c20789e12ee7ae33=<your_registry>/openshift4/ose-csi-external-resizer-rhel7
registry.redhat.io/ocs4/ocs-rhel8-operator@sha256:78b97049b194ebf4f72e29ac83b0d4f8aaa5659970691ff459bf19cfd661e93a=<your_registry>/ocs4/ocs-rhel8-operator
quay.io/noobaa/pause@sha256:b31bfb4d0213f254d361e0079deaaebefa4f82ba7aa76ef82e90b4935ad5b105=<your_registry>/noobaa/pause
quay.io/noobaa/lib-bucket-catalog@sha256:b9c9431735cf34017b4ecb2b334c3956b2a2322ce31ac88b29b1e4faf6c7fe7d=<your_registry>/noobaa/lib-bucket-catalog
registry.redhat.io/ocs4/ocs-must-gather-rhel8@sha256:823e0fb90bb272997746eb4923463cef597cc74818cd9050f791b64df4f2c9b2=<your_registry>/ocs4/ocs-must-gather-rhel8
  ```

- **Mirror the images in `mapping-missing.txt`**  
  ```
  oc image mirror -f mapping-missing.txt --insecure --registry-config=${AUTH_FILE}
  ```

- **Validate imageContentSourcePolicy**  
After `oc adm catalog mirror` is completed it will create the `imageContentSourcePolicy.yaml` file. Check the content of this file for the mirrors mapping shown below. Add any missing entries to the end of the `imageContentSourcePolicy.yaml` file.
 
  ```yaml
  spec:
    repositoryDigestMirrors:
	- mirrors:
	  - <your_registry>/ocs4
	  source: registry.redhat.io/ocs4
	- mirrors:
	  - <your_registry>/rhceph
	  source: registry.redhat.io/rhceph
	- mirrors:
	  - <your_registry>/noobaa
	  source: quay.io/noobaa
	- mirrors:
	  - <your_registry>/openshift4
	  source: registry.redhat.io/openshift4
	- mirrors:
	  - <your_registry>/rhscl
	  source: registry.redhat.io/rhscl  
  ```
- **Apply the `imageContentSourcePolicy.yaml` file to the cluster**  
(the file is generated by `oc adm catalog mirror` and thhe output dir is usually `./[catalog image name]-manifests`)
  ```
  oc apply -f ./[output dir]/imageContentSourcePolicy.yaml
  ```
**Note:** Once the Image Content Source Policy is updated all nodes (master, infra and workers) in the cluster will have to be updated and rebooted. **This process is automatically handled through the Machine Config Pool operator and will take at about 15 minutes although the exact elapsed time will vary based on the number of nodes in your OpenShift cluster.** You can monitor the update process via the `oc get mcp` command or the `oc get node` command.

### Creating the CatalogSource for lib-bucket-provisioner
OCS version 4.4 is dependent on lib-bucket-provisioner which is included in the community-operators catalog. ***If the community-operators catalog is not created, it is necessary to create a custom CatalogSource for the lib-bucket-provisioner.***

- **Create Custom CatalogSource for lib-bucket-provisioner**  
Create a CatalogSource object that references the catalog image for lib-bucket-provisioner. Save it as the lib-bucket-catalogsource.yaml file:
  ```yaml
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
  
  Create the catalogsource:
  ```
  oc apply -f lib-bucket-catalogsource.yaml
  ```
  Verify catalogsource and pod are created:
  
  ```
  oc get catalogsource,pod -n openshift-marketplace | grep lib-bucket
  ```

## Creating the CatalogSource for redhat-operators 
Create a CatalogSource object that references the catalog image for redhat-operators. Modify the following to use <your_registry> and save it as a redhat-operator-catalogsource.yaml file:
  ```yaml
  apiVersion: operators.coreos.com/v1alpha1
  kind: CatalogSource
  metadata:
    name: redhat-operators
    namespace: openshift-marketplace
  spec:
    sourceType: grpc
    icon:
      base64data: PHN2ZyBpZD0iTGF5ZXJfMSIgZGF0YS1uYW1lPSJMYXllciAxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxOTIgMTQ1Ij48ZGVmcz48c3R5bGU+LmNscy0xe2ZpbGw6I2UwMDt9PC9zdHlsZT48L2RlZnM+PHRpdGxlPlJlZEhhdC1Mb2dvLUhhdC1Db2xvcjwvdGl0bGU+PHBhdGggZD0iTTE1Ny43Nyw2Mi42MWExNCwxNCwwLDAsMSwuMzEsMy40MmMwLDE0Ljg4LTE4LjEsMTcuNDYtMzAuNjEsMTcuNDZDNzguODMsODMuNDksNDIuNTMsNTMuMjYsNDIuNTMsNDRhNi40Myw2LjQzLDAsMCwxLC4yMi0xLjk0bC0zLjY2LDkuMDZhMTguNDUsMTguNDUsMCwwLDAtMS41MSw3LjMzYzAsMTguMTEsNDEsNDUuNDgsODcuNzQsNDUuNDgsMjAuNjksMCwzNi40My03Ljc2LDM2LjQzLTIxLjc3LDAtMS4wOCwwLTEuOTQtMS43My0xMC4xM1oiLz48cGF0aCBjbGFzcz0iY2xzLTEiIGQ9Ik0xMjcuNDcsODMuNDljMTIuNTEsMCwzMC42MS0yLjU4LDMwLjYxLTE3LjQ2YTE0LDE0LDAsMCwwLS4zMS0zLjQybC03LjQ1LTMyLjM2Yy0xLjcyLTcuMTItMy4yMy0xMC4zNS0xNS43My0xNi42QzEyNC44OSw4LjY5LDEwMy43Ni41LDk3LjUxLjUsOTEuNjkuNSw5MCw4LDgzLjA2LDhjLTYuNjgsMC0xMS42NC01LjYtMTcuODktNS42LTYsMC05LjkxLDQuMDktMTIuOTMsMTIuNSwwLDAtOC40MSwyMy43Mi05LjQ5LDI3LjE2QTYuNDMsNi40MywwLDAsMCw0Mi41Myw0NGMwLDkuMjIsMzYuMywzOS40NSw4NC45NCwzOS40NU0xNjAsNzIuMDdjMS43Myw4LjE5LDEuNzMsOS4wNSwxLjczLDEwLjEzLDAsMTQtMTUuNzQsMjEuNzctMzYuNDMsMjEuNzdDNzguNTQsMTA0LDM3LjU4LDc2LjYsMzcuNTgsNTguNDlhMTguNDUsMTguNDUsMCwwLDEsMS41MS03LjMzQzIyLjI3LDUyLC41LDU1LC41LDc0LjIyYzAsMzEuNDgsNzQuNTksNzAuMjgsMTMzLjY1LDcwLjI4LDQ1LjI4LDAsNTYuNy0yMC40OCw1Ni43LTM2LjY1LDAtMTIuNzItMTEtMjcuMTYtMzAuODMtMzUuNzgiLz48L3N2Zz4=
      mediatype: image/svg+xml
    image: <your_registry>/olm/redhat-operators:v1
	imagePullPolicy: Always
    displayName: Redhat Operators Catalog
    publisher: Red Hat  
  ```
  Create the catalogsource:
  ```
  oc apply -f redhat-operator-catalogsource.yaml
  ```
  Verify catalogsource and pod are created:
  
  ```
  oc get catalogsource,pod -n openshift-marketplace | grep redhat-operators
  ```
### Updating redhat-operator CatalogSource 
The update process to build and mirror the redhat-operators catalog image is exactly the same as creating the initial catalog image as detailed above in this article. Make sure to modify the ose-operator-registry tag before doing the build and mirror operation (e.g., v4.4 -> v4.5). Best practice is to use the same image tag, v1, for the new redhat-operators image and then restart the redhat-operator pod to get the new image.

  ```
  oc delete $(oc get pod -n openshift-marketplace -o name | grep redhat-operators) -n openshift-marketplace
  ```
  Validate new redhat-operator pod is running
  ```
  oc get pod -n openshift-marketplace | grep redhat-operators
  ```
## Installing OCS using OperatorHub
***OperatorHub*** in the OCP console UI should now present all of the operators in the redhat-operator catalog as well as the lib-bucket-provisioner operator. You can now install OCS 4.4 using the [Deployment Guide][7].

- **The lib-bucket-provisioner CSV and Deployment needs to be edited during Installation**  
Because the CSV, lib-bucket-provisioner.v1.0.0.clusterserviceversion.yaml, does not use a sha for pulling images, quay.io/noobaa/pause will need to be replaced with quay.io/noobaa/pause@sha256:b31bfb4d0213f254d361e0079deaaebefa4f82ba7aa76ef82e90b4935ad5b105. After the deployment of OCS, edit the lib-bucket-provisioner CSV first with this image@sha. Next, edit the lib-bucket-provisioner deployment and replace quay.io/noobaa/pause with this image@sha if not already correct.


[1]:https://access.redhat.com/documentation/en-us/openshift_container_platform/4.4/html/operators/olm-restricted-networks
[2]: https://docs.openshift.com/container-platform/4.4/operators/olm-restricted-networks.html#olm-building-operator-catalog-image_olm-restricted-networks
[3]: https://cloud.redhat.com/openshift/install/pull-secret
[4]: https://access.redhat.com/documentation/en-us/openshift_container_platform/4.4/html/installing/installation-configuration#installing-restricted-networks-preparations
[5]: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.4/
[6]: https://github.com/arvin-a/openshift-disconnected-operators
[7]: https://access.redhat.com/documentation/en-us/red_hat_openshift_container_storage/4.4/html/deploying_openshift_container_storage/deploying-openshift-container-storage-on-openshift-container-platform_rhocs
[8]: https://github.com/red-hat-storage/ocs-training/issues
