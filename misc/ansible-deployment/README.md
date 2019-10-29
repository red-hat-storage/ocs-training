# Ansible scripts to deploy OCS4 on OCP4.2

## Prerequisites
- Ansible ([Installation guide](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html))
- Python packages: openshift, requests


## Installation
Connect to your OpenShift Cluster:
```bash
oc login --token=<replace with your token> --server=<replace with API address of server>
```

Launch with:
```bash
ansible-playbook ocs-deploy.yaml
```

