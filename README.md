# Building a Kubernetes Cluster

> NOTE: this repository is not end-user ready, and may never be! It would probably be pretty easy to adapt it to your needs, though. Mainly I wanted a place to keep all my code for managing my own Kubernetes cluster at home, but I went ahead and made it public and scrubbed out anything sensitive, and partially separated out local configuration, in case others might find it useful.

Keep reading if you'd like to build your own kubernetes cluster meeting this description:
* Runs on CentOS 8 nodes for control plane and workers, minimum of three nodes
* Has three control-plane nodes configured for HA:
   * Each control-plane node runs `keepalived` to manage the api server VIP
   * Each control-plane node runs `haproxy` for distributing load across the api servers
* Runs on bare metal nodes (may work just fine on VMs, but untested)
* Uses [cri-o](https://cri-o.io/) as the container runtime
* Uses [calico](https://www.projectcalico.org/) for cluster networking
* Uses [MetalLB](https://metallb.universe.tf/) for a local layer2 software loadbalancer

> In the parlance of the [kubernetes documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/), this is a Highly Available cluster with stacked control plane nodes.

If all or most of the above is true, just reading the `prep.yaml` playbook and snagging files and templates for your own ansible project could save you a good deal of time, reading and research.

## Structure and Description

This repository is centered around the idea of building and configuring kubernetes cluster-ready nodes using `ansible`, without running any `kubeadm` commands for initializing the cluster or joining nodes. Once the master and worker nodes have been installed and configured, the cluster administrator should use `kubeadm` manually (documented below) for these tasks.

The specialized `template.ks` and `prep.yaml` are tailored for a bare-metal cluster on CentOS 8, using the cri-o container runtime and Calico network driver. Other details:

* Calico is configured with the "50 nodes or less" manifest
* "IPIP" is disabled, and MTU is set to 1500 -> highest performance for L2-connected nodes
* Some of the configuration is specific to a home network installation

There are two primary parts / steps for cluster builds:
* the `prep.yaml` ansible playbook performs all the basic configuration required for a cluster node:
  * installation of `cri-o` and required configuration
  * installs kubernetes binaries `kubeadm`, `kubectl` and `kubelet`
  * creates `/root/kubeadm-config.yaml` for use with `kubeadm init`
  * creates `/home/calico.yaml` to add the calico network driver
  * creates `/home/metallb.yaml` for MetalLB configuration
* the remainder of cluster operations, including initializing the cluster and adding nodes, is done with `kubeadm` and `kubectl`

# Other Documentatation
* [etcd operations](docs/etcd.md)

## Creating a New Cluster Step-by-Step

> Note that these instructions were compiled primarily from documentation at [the official Kubernetes site](https://kubernetes.io) and [the Calico project](https://projectcalico.org).

### 0 - Installing the Node OS

Each cluster node needs to be installed with CentOS 8, with no swap. The template used for installation can be found in `template.ks`. The `ssh-key` there should be the public key for the user that will be running the playbook.

### 1 - Set up the Inventory, Group Vars, and local.yaml

All cluster nodes should be listed in `inventory/home/hosts.yaml`, with control-plane nodes listed in the `kube-master` group. If you create your own inventory, you might want to edit `ansible.cfg` to reflect this, since the instructions below don't specify the inventory to use.

The variables for this playbook are all defined in two locations:
* `inventory/home/group_vars/all/all.yaml`, for standard non-sensitive values
* `group_vars/all/secrets.yaml` - a file that you should supply to override secret values in the inventory file

Examine and update the vars per your local configuration. Note that `k8s_master_vip` should be set to the value for the floating VIP; an IP from the local subnet not assigned to any physical node.

### 2 - Prep the Nodes

With the nodes installed, you can now run the `prep.yaml` playbook from the manager workstation:
```
$ ansible-playbook prep.yaml
...
```
> Note that `ansible.cfg` sets the inventory, remote user, and other items.

### 3 - Running kubeadm init

With all the nodes installed and prepped, you can log in to the first master node, sudo to root, and initialize the cluster:
```
$ ssh bootstrap@master1
$ sudo su
# cd
# kubeadm init --config=kubeadm-config.yaml --upload-certs | tee kubeadm-init.out
```

### 4 - Setting up non-privileged user

Once you've run `kubeadm init`, you can perform the remaining steps non-privileged. As the `bootstrap` user:
```
$ mkdir .kube
$ sudo cp -i /etc/kubernetes/admin.conf .kube/config
$ sudo chown bootstrap:bootstrap .kube/config
$ echo -e "source <(kubectl completion bash)\nalias k=kubectl\ncomplete -F __start_kubectl k" >> .bashrc
```
Now log out and back in to enable the `k` alias for `kubectl` and bash completion.

### 5 - Installing Calico

Now that you can operate the cluster as the `bootstrap` user, apply the ansible-provided `calico.yaml` to install Calico:
```
$ k apply -f /home/calico.yaml
...
```
> Note that `calico.yaml` has a couple of small modifications from the stock version; the MTU is raised to 1500, and an extra environment variable was added for Felix to use the `NFT` iptables backend, required for CentOS 8.

### 6 - Fixing DNS Resolution / Calico

First - wait for all the Calico pods to progress to status: Running. Calico needs to be running for this to work.

I don't know if this is a known issue, but when the cluster was first created pods were not able to resolve DNS. Examining the running pods, several had IP addresses outside the configured range; example:
```
kube-system   calico-kube-controllers-854c58bf56-2km8x      1/1     Running   0          7h2m    10.85.0.4        master1.localdomain   <none>           <none>
kube-system   coredns-66bff467f8-njls2                      1/1     Running   0          4m11s   10.85.0.2        master2.localdomain   <none>           <none>
kube-system   coredns-66bff467f8-pvd67                      1/1     Running   0          4m29s   10.85.0.3        worker1.localdomain   <none>           <none>
```

After deleting these pods and letting them re-create, they all came up with proper `10.42.x.y` addresses, and DNS resolution worked.

### 7 - Adding a Worker Node

With the cluster essentially running, now you can add a worker node using the commands shown at the end of `kubeadm-init.out`; e.g.:
```
kubeadm join k8smaster:7443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

> Note that the above command assumes you kept the default values for `k8s_master_hostname` (k8smaster), and `k8s_master_port` (7443); you'll need to modify the command you used if you changed these values - the output from `kubeadm init` should be correct.

If the token has expired, you can create a new one with `kubeadm token create`; the cert hash is the same.

### 8 - Adding a Control Plane Node

To expand the control plane on inventory hosts listed as `master`, use the command for adding control plane nodes given in `kubeadm-init.out`:

```
# kubeadm join k8smaster:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --control-plane --certificate-key <certificate-key>
```

> Note that the above command assumes you kept the default values for `k8s_master_hostname` (k8smaster), and `k8s_master_port` (7443); you'll need to modify the command you used if you changed these values - the output from `kubeadm init` should be correct.

If the token and/or certificate key have expired, this command may just hang instead of giving an error message. To generate new items from the first master node:
* Token: `kubeadm token create` (command hangs)
* Certificate key: `kubeadm init phase upload-certs --upload-certs` (error message)

### 9 - (Optional) Remove Master Node Taints

For small clusters that should allow workloads to run on control-plane nodes, you can remove the taints:
```
$ kubectl taint nodes --all node-role.kubernetes.io/master-
```

### 10 - Add the MetalLB Software Load Balancer

[MetalLB](https://metallb.universe.tf/) is very similar to `keepalived`, and probably the best-known software loadbalancer for Kubernetes bare-metal installs. The `prep.yaml` playbook creates a `/home/metallb.yaml` to configure a loadbalancer opering in layer2 mode.

The ansible-provided `kubeadm-config.yaml` already configures `kube-proxy` in "ipvs" mode with "strictARP: true", so you can proceed straight to installation. From the website, here's how you can install by manifest:
```
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.4/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.4/manifests/metallb.yaml
# On first install only
kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
```

Once installed, you can configure MetalLB by applying the generated `metallb.yaml`:
```
$ kubectl apply -f /home/metallb.yaml
configmap/config created
```

### 11 - Configure Longhorn Cluster Storage

[Longhorn](https://longhorn.io/), originally created by [Rancher Labs](https://rancher.com/), is one of the easier resilient cluster storage solutions.

#### 11a - Label storage nodes

In a small cluster of only a few permanent nodes, you can label them all for storage:
```
$ kubectl label nodes --all node.longhorn.io/create-default-disk=true
```

#### 11b - Install with Helm

This repository includes an appropriate `longhorn-values.yaml` for use with helm 3:
```
$ cd ..
$ git clone https://github.com/longhorn/longhorn
$ kubectl create namespace longhorn-system
$ helm install longhorn ./longhorn/chart/ --namespace longhorn-system --values kubeadm-home/longhorn-values.yaml
```

#### 11c - Accessing the UI

Once all pods are running, you can access the UI by using `kubectl port-forward`:
```
$ kubectl -n longhorn-system port-forward service/longhorn-frontend 8080:80
```

Now you can access the Longhorn UI at [localhost:8080](http://localhost:8080).

## Upgrading the Cluster

***NOTE NOTE NOTE:*** These instructions were created for a home/devel cluster, and skips steps such as draining nodes that would probably be pretty important for production clusters. You've been warned and YMMV.

### 1 - Upgrade `cri-o`

Per the developers, `cri-o` should be backward-compatible with older versions of `kubernetes`. Modify the `crio_minor_version` and `crio_version` for the minor version matching your target cluster version, and the most recent point version. For example, when upgrading kubernetes 1.19.7 -> 1.20.2, I first upgrade `cri-o` to 1.20.0, the most latest point version of 1.20.

Once you've updated the variables, run the `prep.yaml` playbook, then reboot the nodes.

### 2 - Follow the official kubernetes upgrade instructions

Note I skipped the part about draining nodes, and at the end I just upgraded the kubelets and rebooted the nodes.

When upgrading `calico`, use the saved `*.orig.yaml` and create a diff against the template `calico.j2`; changes will need to be propagated to a new `calico.j2` template based on the newer calico version.
