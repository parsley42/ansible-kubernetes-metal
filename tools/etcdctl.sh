#!/bin/bash

if [ $# -lt 2 ]
then
    echo "Usage: etcdctl.sh <#> <cmd>"
    exit 0
fi

NODE=$1
shift

kubectl -n kube-system exec -it etcd-${NODE}.localdomain -- \
    etcdctl --cacert /etc/kubernetes/pki/etcd/ca.crt \
    --key /etc/kubernetes/pki/etcd/server.key \
    --cert /etc/kubernetes/pki/etcd/server.crt "$@"
