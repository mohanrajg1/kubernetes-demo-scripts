 #!/bin/bash

PGPASSWORD=$(kubectl get secret --namespace default ${1}-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode; echo)
KUBECTL=/usr/bin/kubectl

case "$2" in
  init)
    size=${3:-100}
    read -r -d '' COMMAND <<-EOF
    $KUBECTL run --namespace default ${1}-postgresql-pgbench-init \
      --restart=Never --rm --tty -i \
      --image postgres --env "PGPASSWORD=$PGPASSWORD"  \
      --command -- pgbench -i -s $size -U postgres  -h ${1}-postgresql postgres
    EOF
  ;;
  shell)
    read -r -d '' COMMAND <<-EOF
    $KUBECTL run --namespace default ${1}-postgresql-pgbench-shell \
      --restart=Never --rm --tty -i \
      --image postgres --env "PGPASSWORD=$PGPASSWORD"  \
      --command -- psql -U postgres  -h ${1}-postgresql postgres
    EOF
  ;;
  bench)
    transactions=${3:-5000}
    clients=${4:-80}
    read -r -d '' COMMAND <<-EOF
    $KUBECTL run --namespace default ${1}-postgresql-pgbench \
      --restart=Never --rm --tty -i \
      --image postgres --env "PGPASSWORD=$PGPASSWORD"  \
      --command -- pgbench -c $clients -t $transactions -U postgres  -h ${1}-postgresql postgres
    EOF
  ;;
    kill-and-move)
      NODE=`$KUBECTL get pods -o wide | grep ${1}-postgresql | awk '{print $7}'`
      POD=`$KUBECTL get pods -o wide | grep ${1}-postgresql | awk '{print $1}'`
      read -r -d '' COMMAND <<-EOF
      $KUBECTL taint node $NODE key=value:NoSchedule && kubectl delete pod $POD
      EOF
  ;;
esac
echo $COMMAND
eval $COMMAND
