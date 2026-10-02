# Deployment and validation

## Prerequisites

Install Docker, kind, kubectl, and curl. Start Docker and make sure `docker info` succeeds. Port 30007 must be available. The first deployment requires internet access to download images and dependencies. Allow enough Docker CPU and memory for three Kubernetes nodes, three MySQL pods, and the application. MySQL pods request 3 GiB of memory in total.

This repository is a local learning deployment. It uses sample credentials and Django's development server.

## Deploy

Run from the repository root:

```bash
./bootstrap.sh
```

The script creates the `todoapp` kind cluster if it does not exist, builds and loads `todoapp:local`, creates both namespaces, deploys MySQL, waits for all three database pods, runs Django migrations, and deploys the application. It stops if a required step fails.

To choose a different cluster name:

```bash
CLUSTER_NAME=todoapp-practice ./bootstrap.sh
```

An existing cluster must have the port mapping from `cluster.yml`. The script does not rebuild an existing cluster. Repeated runs preserve MySQL PVCs and rerun migrations. Avoid concurrent runs for the same cluster. When changing application code, rerun the script to rebuild the image and restart the Deployment.

The commands below assume the default cluster name. For a custom name, replace `kind-todoapp` with the corresponding context.

## Validate Kubernetes resources

```bash
kubectl --context kind-todoapp get namespaces mysql todoapp
kubectl --context kind-todoapp -n mysql get statefulset mysql
kubectl --context kind-todoapp -n mysql get pods -l app=mysql
kubectl --context kind-todoapp -n mysql get pvc
kubectl --context kind-todoapp -n mysql get service mysql
kubectl --context kind-todoapp -n todoapp get deployment,pods,services,jobs
```

Expected results:

- The StatefulSet has three ready replicas: `mysql-0`, `mysql-1`, and `mysql-2`.
- `data-mysql-0`, `data-mysql-1`, and `data-mysql-2` are Bound.
- The MySQL Service has `CLUSTER-IP` set to `None`.
- The `todoapp-migrate` Job is Complete and the application pod is Ready.
- The application NodePort is 30007.

Each MySQL pod has its own database and PVC. This task does not configure database replication. Django connects specifically to `mysql-0.mysql.mysql.svc.cluster.local`.

## Validate the application and database

```bash
curl --fail http://localhost:30007/api/health
curl --fail http://localhost:30007/api/ready
kubectl --context kind-todoapp -n todoapp logs job/todoapp-migrate
kubectl --context kind-todoapp -n todoapp exec deployment/todoapp -- python manage.py check
kubectl --context kind-todoapp -n todoapp exec deployment/todoapp -- python manage.py migrate --check
kubectl --context kind-todoapp -n mysql exec mysql-0 -- sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" mysql -h 127.0.0.1 -u "$MYSQL_USER" "$MYSQL_DATABASE" -e "SHOW TABLES;"'
```

Both HTTP checks should return status 200. The database should contain Django tables, including `django_migrations`, `auth_user`, and the ToDo application tables.

Open http://localhost:30007, register a user, and create a list and a task. Confirm they remain visible after refreshing the page.

## Validate persistent storage

After creating a task, recreate only the first database pod:

```bash
kubectl --context kind-todoapp -n mysql delete pod mysql-0
kubectl --context kind-todoapp -n mysql rollout status statefulset/mysql --timeout=600s
kubectl --context kind-todoapp -n todoapp rollout status deployment/todoapp --timeout=300s
curl --fail http://localhost:30007/api/ready
```

Refresh the application and confirm the user, list, and task still exist. The PVC must remain in place during this check. The readiness endpoint can temporarily return 503 while MySQL restarts.

The `init.sql` file is supplied by `configMap.yml` and mounted into `/docker-entrypoint-initdb.d`. MySQL executes initialization scripts only when its data directory is empty. Editing the SQL or initialization credentials does not update an already initialized database. For an existing database, apply account changes explicitly in MySQL; for a disposable practice environment, recreate the cluster only when its data is no longer needed.

## Troubleshooting

```bash
kubectl --context kind-todoapp -n mysql describe pod mysql-0
kubectl --context kind-todoapp -n mysql logs mysql-0
kubectl --context kind-todoapp -n mysql get events --sort-by=.metadata.creationTimestamp
kubectl --context kind-todoapp -n todoapp describe deployment todoapp
kubectl --context kind-todoapp -n todoapp logs deployment/todoapp
kubectl --context kind-todoapp -n todoapp logs job/todoapp-migrate
kubectl --context kind-todoapp get storageclass
```

For Pending PVCs, inspect the `standard` StorageClass and the kind storage provisioner. For Pending pods, check available node resources. For image errors, rebuild and load `todoapp:local` into the correct cluster. For database authentication errors, verify that both Secrets use the same user and password and that the existing database account matches them.

## Submission

Commit the changes in your fork, open a pull request, and submit its URL on the validation platform.

## References

- [kind quick start](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [Official MySQL image initialization](https://hub.docker.com/_/mysql)
