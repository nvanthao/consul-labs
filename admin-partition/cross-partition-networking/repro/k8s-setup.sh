#! /usr/bin/bash

hs consul-k8s

kubectl create ns consul
kubectl -n consul create secret generic --from-literal=key=$(cat license) license
kubectl -n consul create secret generic --from-literal=key=root bootstrap-acl-token
