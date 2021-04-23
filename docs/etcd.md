# Managing etcd

This repository includes the `tools/etcdctl.sh` script for running `etcdctl` commands in the master nodes:
```
$ ./etcdctl.sh
Usage: etcdctl.sh <node> <cmd>
```

Where `<node>` is the node to run the command against, and `<cmd>` is the etcdctl command to run. For example:
```
$ ./etcdctl.sh master1 member list
4800f60188df8489, started, master2.localdomain, https://192.168.86.107:2380, https://192.168.86.107:2379, false
608b920927626242, started, master3.localdomain, https://192.168.86.108:2380, https://192.168.86.108:2379, false
d6d441c0918e12d0, started, master1.localdomain, https://192.168.86.110:2380, https://192.168.86.110:2379, false
$ ./etcdctl.sh master1 endpoint status --cluster
https://192.168.86.107:2379, 4800f60188df8489, 3.4.3, 3.1 MB, false, false, 2, 739538, 739538, 
https://192.168.86.108:2379, 608b920927626242, 3.4.3, 3.1 MB, false, false, 2, 739538, 739538, 
https://192.168.86.110:2379, d6d441c0918e12d0, 3.4.3, 3.1 MB, true, false, 2, 739538, 739538,
```

> Note: this script has the built-in assumptions that the actual node name is `<node>.localdomain` (`master1` -> `master1.localdomain`), and that the pod name for the node is `etcd-<full-node-name>`. These should hold true if no major modifications were made during install.

# Database Backup

Since the etcd container users a hostPath mount for `/var/lib/etcd`, you can use the script for creating a backup there:
```
$ ./etcdctl.sh master1 snapshot save /var/lib/etcd/snapshot.db
{"level":"info","ts":1599583406.8910177,"caller":"snapshot/v3_snapshot.go:110","msg":"created temporary db file","path":"/var/lib/etcd/snapshot.db.part"}
{"level":"warn","ts":"2020-09-08T16:43:26.896Z","caller":"clientv3/retry_interceptor.go:116","msg":"retry stream intercept"}
{"level":"info","ts":1599583406.8966873,"caller":"snapshot/v3_snapshot.go:121","msg":"fetching snapshot","endpoint":"127.0.0.1:2379"}
{"level":"info","ts":1599583406.9295232,"caller":"snapshot/v3_snapshot.go:134","msg":"fetched snapshot","endpoint":"127.0.0.1:2379","took":0.038469946}
{"level":"info","ts":1599583406.9296036,"caller":"snapshot/v3_snapshot.go:143","msg":"saved","path":"/var/lib/etcd/snapshot.db"}
Snapshot saved at /var/lib/etcd/snapshot.db
```

# Database Restore - TBD

Currently, the proper way to restore the etcd database for a cluster built this way is not determined.
