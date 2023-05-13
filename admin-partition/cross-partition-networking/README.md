# Objective
To understand Admin Partition cross-partition networking feature

We gonna have an `frontend` app talks to `backend` app across 2 admin partition `foo` and `bar`. 
The app is deployed as `Pod` in 2 Kubernetes clusters

![app](admin-partition/cross-partition-networking/app.png)
![arch](admin-partition/cross-partition-networking/arch.png)

# Requirements

- Consul Enterprise >= 1.15.2
- Valid Consul Enterprise license
- Multipass >= 1.11.1

# Instructions

## Launch 2 Multipass VMs to install 2 K8S clusters
We gonna use `k3s`

```
multipass launch -c 2 -m 4G -d 10G -n k8s-foo --cloud-init k3s.yaml
multipass launch -c 2 -m 4G -d 10G -n k8s-bar --cloud-init k3s.yaml
multipass mount repro k8s-foo:/home/ubuntu/repro
multipass mount repro k8s-bar:/home/ubuntu/repro
```

## Run Consul Server in host
Multipass will connect all instances to a virtual switch of `subnet 192.168.64.*`. We will utilize this address for Consul server running on host. More info [link](https://multipass.run/docs/troubleshoot-networking#heading--architecture)

Run the Consul server

```
consul agent -server -bootstrap -node s1 -bind 192.168.64.1 -client 0.0.0.0 -data-dir ./data/s1 -hcl 'acl { enabled = true default_policy = "deny" tokens { initial_management = "root" } }' -hcl 'ports { grpc = 8502 }' -hcl 'connect { enabled = true }' -ui -log-level debug
```

**NOTE:** We are using `root` for ACL root token for simplicity

## SSH into the VMs
Open 2 terminal tabs or Tmux panes

```
multipass shell k8s-foo
multipass shell k8s-bar
```


## Create required secrets
For each cluster
```
k create secret generic --from-literal=key=$(cat license) license
k create secret generic --from-literal=key=root bootstrap-acl-token
```

## Install K8S on foo cluster

```
cd repro
hs consul-k8s
consul-k8s install -f foo-values.yaml --namespace consul --wait --verbose --auto-approve
```

## Install K8S on bar cluster

```
cd repro
hs consul-k8s
consul-k8s install -f bar-values.yaml --namespace consul --wait --verbose --auto-approve
```

## Install sample app frontend on foo

```
k apply -f frontend.yaml
```

## Install sample app backend on bar

```
k apply -f backend.yaml
```

## Enable the cross-partition networking communication

For `frontend` to talk to `backend`, we will have to ensure these settings in `bar` instance:

### Export service from bar to foo

```
k apply -f exported-services.yaml
```

**NOTE:** We will have to export `mesh-gateway` as well

### Have correct intention

```
k apply -f intention.yaml
```

This is so that Transparent Proxy feature can infer the upstream for downstream and set the Envoy config accordingly

### Set mesh-gateway proxy default to local

```
k apply -f proxy-defaults.yaml
```

### Set the upstream URL [correctly](https://developer.hashicorp.com/consul/docs/services/discovery/dns-static-lookups#service-virtual-ip-lookups-for-consul-enterprise)

```
http://backend.virtual.default.ns.bar.ap.consul:9001
```

## Observations

From host, we can see the Virtual IP of backend

```
dig @127.0.0.1 -p 8600 backend.virtual.default.ns.bar.ap.consul
```

Inside the cluster, we can peek into the Envoy settings for sidecar of the app and Mesh Gateway sidecar

```
k debug -n consul consul-mesh-gateway-<pod>-zg4lm -it --image nicolaka/netshoot -- sh
curl 0:19000/clusters
curl 0:19000/config_dump?include_eds
```