# PostgreSQL Helm Kubernetes Demo

This demo is designed to show VxFlex OS integration with Kubernetes to support a single-instance stateful application. In this case, [PostgreSQL Database](https://postgresql.org).

## Requirements

This demo assumes the existence of a Kubernetes cluster with the following requirements:
* A Kubernetes cluster with two or more worker nodes _(this is required to see the data move between hosts)_
* VxFlex OS based Default Storage Class (this can be either the [_"in-tree"_](https://github.com/kubernetes/examples/tree/master/staging/volumes/scaleio) or [CSI-based](https://github.com/thecodeteam/csi-scaleio) driver).
* [Helm ](https://helm.sh/) Kubernetes Package Manager
* A user with credentials to deploy a Helm release and access

> _**Tip:** With Helm deployed, you can easily install VxFlex CSI integration with the [VxFlex OS CSI chart](https://github.com/VxFlex-OS/charts/tree/master/vxflex-csi)_

## Instructions

**1. Download the [`pg_bench.sh`](pgbench_script.sh) for easy access to `kubectl` several kubectl commands later in the demo.**

```bash
$ wget https://raw.githubusercontent.com/VxFlex-OS/kubernetes-demo-scripts/master/posgresql/pgbench_script.sh
$ chmod +x pgbench_script.sh
```

**2. Check that the storage class exists and is the default**

```bash
$ kubectl get storageclass
NAME               PROVISIONER   AGE
vxflex (default)   csi-scaleio   9h
```
> _This is an example. Your own storage class name and provisioner may differ._

**3. Install PostgreSQL using Helm:**
> _The "release name" below (invinvible-bear) is autogenerated by helm. Yours will differ._
```bash
$ helm install stable/postgresql
AME:   invinvible-bear
LAST DEPLOYED: Tue May 22 09:50:13 2018
NAMESPACE: default
STATUS: DEPLOYED

RESOURCES:
==> v1/Secret
NAME                        TYPE    DATA  AGE
invinvible-bear-postgresql  Opaque  1     0s

==> v1/ConfigMap
NAME                        DATA  AGE
invinvible-bear-postgresql  0     0s

==> v1/PersistentVolumeClaim
NAME                        STATUS   VOLUME  CAPACITY  ACCESS MODES  STORAGECLASS  AGE
invinvible-bear-postgresql  Pending  vxflex  0s

==> v1/Service
NAME                        TYPE       CLUSTER-IP     EXTERNAL-IP  PORT(S)   AGE
invinvible-bear-postgresql  ClusterIP  10.109.25.135  <none>       5432/TCP  0s

==> v1beta1/Deployment
NAME                        DESIRED  CURRENT  UP-TO-DATE  AVAILABLE  AGE
invinvible-bear-postgresql  1        1        1           0          0s

==> v1/Pod(related)
NAME                                         READY  STATUS   RESTARTS  AGE
invinvible-bear-postgresql-57748777b4-t79r5  0/1    Pending  0         0s

<snip />
```

**4. Ensure that the pod is running**
> _**Tip:** This typically happens within a minute. If its taking longer troubleshoot the storage by looking at either the `kube-controller-manager` (for in-tree driver) or the `csi-controller` (for CSI)_.

```bash
$ kubectl get all -l release=invinvible-bear
NAME                                              READY     STATUS    RESTARTS   AGE
pod/invinvible-bear-postgresql-57748777b4-t79r5   1/1       Running   0          5m

NAME                                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/invinvible-bear-postgresql   ClusterIP   10.109.25.135   <none>        5432/TCP   5m

NAME                                         DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/invinvible-bear-postgresql   1         1         1            1           5m

NAME                                                    DESIRED   CURRENT   READY     AGE
replicaset.apps/invinvible-bear-postgresql-57748777b4   1         1         1         5m
```

**5. Initialize the PG Bench database using the script**

```bash
$ ./pgbench_script.sh invinvible-bear init
/usr/bin/kubectl run --namespace default invinvible-bear-postgresql-pgbench-init --restart=Never --rm --tty -i --image postgres --env "PGPASSWORD=XXX" --command -- pgbench -i -s 100 -U postgres -h invinvible-bear-postgresql postgres
If you don't see a command prompt, try pressing enter.
600000 of 10000000 tuples (6%) done (elapsed 0.70 s, remaining 11.04 s)
...
10000000 of 10000000 tuples (100%) done (elapsed 18.26 s, remaining 0.00 s)
vacuum...
set primary keys...
done.
```
**6. Benchmark the storage using `pgbench`:**

```bash
./pgbench_script.sh invinvible-bear bench
/usr/bin/kubectl run --namespace default invinvible-bear-postgresql-pgbench --restart=Never --rm --tty -i --image postgres --env "PGPASSWORD=DxFcIqKyqT" --command -- pgbench -c 80 -t 5000 -U postgres -h invinvible-bear-postgresql postgres
If you don't see a command prompt, try pressing enter.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 100
query mode: simple
number of clients: 80
number of threads: 1
number of transactions per client: 5000
...
```

**7. You can open a shell to the database, if you'd like to poke around.**

```bash
$ ./pgbench_script.sh invinvible-bear shell
/usr/bin/kubectl run --namespace default invinvible-bear-postgresql-pgbench-shell --restart=Never --rm --tty -i --image postgres --env "PGPASSWORD=XXX" --command -- psql -U postgres -h invinvible-bear-postgresql postgres
If you don't see a command prompt, try pressing enter.
postgres=# select * from pgbench_history;
tid  | bid |   aid   | delta |           mtime            | filler
------+-----+---------+-------+----------------------------+--------
  873 |  67 | 3378822 | -2411 | 2018-05-22 19:11:25.149033 |
  862 |  90 |  375810 | -3208 | 2018-05-22 19:11:25.148735 |
...
postgres=# \q
```

**8. In another shell, watch the state of the containers, so that we can see what happens when we kill it.**

```bash
$ kubectl get pods -l 'release=invinvible-bear' -o wide -w
NAME                                          READY     STATUS    RESTARTS   AGE       IP           NODE
invinvible-bear-postgresql-57748777b4-mppf2   1/1       Running   0          1m        10.244.1.7   node00
```

**9. Now, execute a couple of commands to kill the container, and ensure that it moves to another host.**

```bash
$ ./pgbench_script.sh invinvible-bear kill-and-move
kubectl taint node node00 key=value:NoSchedule && \
  kubectl delete pod invinvible-bear-postgresql-57748777b4-t79r5
node "node00" tainted
pod "invinvible-bear-postgresql-57748777b4-t79r5" deleted
```

**10. In our other shell, we'll see that container be terminated, and recreated on another host.**

```bash
$ kubectl get pods -l 'release=invinvible-bear' -w -o wide
NAME                                          READY     STATUS              RESTARTS   AGE       IP           NODE
invinvible-bear-postgresql-57748777b4-mppf2   1/1       Running             0          1m        10.244.1.7   node00
invinvible-bear-postgresql-57748777b4-mppf2   1/1       Terminating         0          2m        10.244.1.7   node00
invinvible-bear-postgresql-57748777b4-ll6wh   0/1       Pending             0          0s        <none>       <none>
invinvible-bear-postgresql-57748777b4-ll6wh   0/1       Pending             0          0s        <none>       node01
invinvible-bear-postgresql-57748777b4-ll6wh   0/1       ContainerCreating   0          0s        <none>       node01
invinvible-bear-postgresql-57748777b4-ll6wh   0/1       Running             0          45s       10.244.0.5   node01
```

**11. Feel free to validate that your data is still available.**

```bash
$ ./pgbench_script.sh invinvible-bear shell
/usr/bin/kubectl run --namespace default invinvible-bear-postgresql-pgbench-shell --restart=Never --rm --tty -i --image postgres --env "PGPASSWORD=DxFcIqKyqT" --command -- psql -U postgres -h invinvible-bear-postgresql postgres
If you don't see a command prompt, try pressing enter.
postgres=# select * from pgbench_history;
 tid  | bid |   aid   | delta |           mtime            | filler
------+-----+---------+-------+----------------------------+--------
  873 |  67 | 3378822 | -2411 | 2018-05-22 19:11:25.149033 |
  862 |  90 |  375810 | -3208 | 2018-05-22 19:11:25.148735 |
  ...
```

**12. High-five your neighbor 🙌. Stateful containers with persistent storage, FTW.**
