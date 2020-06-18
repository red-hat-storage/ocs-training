# Disconnected Install for OpenShift Container Storage

This doc is based on [this document][1]

## Motivation
In a disconnected environment there is no access to the OLM catalog and the image registries, so in order to install OCS we need to do 2 things:
1. provide a custom catalog that contains OCS CSV (cluster service version)
    - this is done using the command `oc adm catalog build`. this command is going over a given catalog (e.g. redhat-operators), builds an olm catalog image and pushes it to the mirror registry.
    - to work around the issue of `lib-bucket-provisioner` which is a dependency in community-operators we will need to build a catalog image for community-operators as well. once this issue will be fixed this will be unnecessary.
2. mirror all images that are required by OCS to a mirror registry which is accessible from the OCP cluster
    - this is done using the command `oc adm catalog mirror`. this command goes over the CSVs in the catalog and copy all required images to the mirror registry.
    - to work around the missing `relatedImages` in OCS CSV, we will need to manually mirror required images which are not copied with `oc adm catalog mirror`. this is done using `oc image mirror`
    - `oc adm catalog mirror` generates `imageContentSourcePolicy.yaml` to install in the cluster. this resource tells OCP what is the mapping each image in the mirror registry. we need to add to it also the mapping of the related images before applying in the cluster.



## prerequisites
1. assuming that a disconnected cluster is already installed and a mirror registry exists on a bastion host ([see here][4]).   
The following steps can also be applied and tested on a connected cluster. since we disable the default catalog (operator hub), the flow should be similar on both connected and disconnected envs
2. oc is installed and logged in to the cluster. I used [oc 4.4][5], for earlier versions thigs might not work as well


## env vars (fill the correct details for your setup)
  ```
  export AUTH_FILE="~/podman_config.json"
  export MIRROR_REGISTRY_DNS="<your_registry>"
  ```


## create auth file
* get redhat registry [pull secret][3] and paste it to `${AUTH_FILE}`
* podman login to the mirror registry and store the credentials in `${AUTH_FILE}`
  ```
  podman login ${MIRROR_REGISTRY_DNS} --tls-verify=false --authfile ${AUTH_FILE}
  ```
you should eventually get something similar to this:
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



## Building and mirroring the Operator catalog image

- **build oeprators catalog for redhat operators**  
The tag of the `origin-operator-registry` in the `--from` flag should match the major and minor versions of the OCP cluster (e.g. 4.3)
  ```
  oc adm catalog build --insecure --appregistry-endpoint https://quay.io/cnr --appregistry-org redhat-operators --from=quay.io/openshift/origin-operator-registry:4.4 --to=${MIRROR_REGISTRY_DNS}/olm/redhat-operators:v1 --registry-config=${AUTH_FILE}
  ```

- **mirror the redhat-operators catalog**  
This is a long operation and should take ~1-2 hours. It requires ~60-70 GB of disk space on the bastion (the mirror machine)
  ```
  oc adm catalog mirror ${MIRROR_REGISTRY_DNS}/olm/redhat-operators:v1 ${MIRROR_REGISTRY_DNS}  --insecure --registry-config=${AUTH_FILE}
  ```

- **Disable the default OperatorSources by adding disableAllDefaultSources: true to the spec**
  ```
  oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
  ```

## **OCS-4.4.0 workarounds** 


### relatedImages workarounds

  In OCS-4.4 the relatedImages are in the CSV for the most part. Even so we still need to add a few missing images that are not yet in the OCS 4.4 CSV relatedImages. Below is an example of a mapping file for OCS-4.4.0 that includes the missing images.

  mapping.txt for OCS-4.4.0:
  
  ```
registry.redhat.io/openshift4/ose-csi-external-resizer-rhel7@sha256:e7302652fe3f698f8211742d08b2dcea9d77925de458eb30c20789e12ee7ae33=<your_registry>/openshift4/ose-csi-external-resizer-rhel7

registry.redhat.io/ocs4/ocs-rhel8-operator@sha256:78b97049b194ebf4f72e29ac83b0d4f8aaa5659970691ff459bf19cfd661e93a

quay.io/noobaa/pause@sha256:b31bfb4d0213f254d361e0079deaaebefa4f82ba7aa76ef82e90b4935ad5b105=<your_registry>/noobaa/pause

quay.io/noobaa/lib-bucket-catalog@sha256:b9c9431735cf34017b4ecb2b334c3956b2a2322ce31ac88b29b1e4faf6c7fe7d=<your_registry>/noobaa/lib-bucket-catalog

registry.redhat.io/ocs4/ocs-must-gather-rhel8@sha256:823e0fb90bb272997746eb4923463cef597cc74818cd9050f791b64df4f2c9b2=<your_registry>/ocs4/ocs-must-gather-rhel8
  ```

- **Mirror the images in `mapping.txt`**  
  ```
  oc image mirror -f mapping.txt --insecure --registry-config=${AUTH_FILE}
  ```


- **Validate imageContentSourcePolicy**  
After `oc adm catalog mirror` is completed it will print an output dir where an `imageContentSourcePolicy.yaml` is generated. Check the content of this file for the mirrors shown below. Add any missing mirrors.
 
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

### lib-bucket-provisioner workarounds

OCS version 4.4 is still dependent on lib-bucket-provisioner which is included in the community-operators catalog. If this catalog is not created to work around this dependency it's necessary to create a custom CatalogSource pointing to the lib-bucket-provisoner image that was mirrored in previous step.

- **Create Custom CatalogSource for lib-bucket-provisioner**  
Create a CatalogSource object that references the catalog image for lib-bucket-provisioner. Save it as for example the catalogsource.yaml file:
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
  
  create the catalog source:
  ```
  oc create -f catalogsource.yaml
  ```

- **The lib-bucket-provisioner CSV and Deployment need to be edited**  
The image quay.io/noobaa/pause will need to be replaced with quay.io/noobaa/pause@sha256:b31bfb4d0213f254d361e0079deaaebefa4f82ba7aa76ef82e90b4935ad5b105. After the deployment of OCS, edit the lib-bucket-provisioner CSV first with this image@sha. Next, edit the lib-bucket-provisioner deployment and replace quay.io/noobaa/pause with this image@sha if not already correct.

## Normal path (after workarounds)

- **After adding the related images (in the `relatedImages workarounds` section), apply the `imageContentSourcePolicy.yaml` file to the cluster**  
(the file is generated by `oc adm catalog mirror`. the output dir is usually `./[catalog image name]-manifests`)
  ```
  oc apply -f ./[output dir]/imageContentSourcePolicy.yaml
  ```

- **Create CatalogSource for redhat-operators**  
Create a CatalogSource object that references the catalog image for redhat-operators. Modify the following to your specifications and save it as a catalogsource.yaml file:
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
    displayName: Redhat Operators Catalog
    publisher: Red Hat  
  ```
  create the catalog source:
  ```
  oc create -f catalogsource.yaml
  ```


All Done!



the ***Operators*** section in the UI should now present all of the catalog content, and you can install OCS from the mirror registry

[1]:https://docs.openshift.com/container-platform/4.4/operators/olm-restricted-networks.html#olm-restricted-networks-operatorhub_olm-restricted-networks
[2]: https://docs.openshift.com/container-platform/4.4/operators/olm-restricted-networks.html#olm-building-operator-catalog-image_olm-restricted-networks
[3]: https://cloud.redhat.com/openshift/install/pull-secret
[4]: https://access.redhat.com/documentation/en-us/openshift_container_platform/4.4/html/installing/installation-configuration#installing-restricted-networks-preparations
[5]: https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest-4.4/
