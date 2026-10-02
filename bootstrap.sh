#!/usr/bin/env bash
set -Eeuo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
CLUSTER_NAME="${CLUSTER_NAME:-todoapp}"

for tool in docker kind kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required command not found: $tool" >&2
    exit 1
  fi
done
docker info >/dev/null

if ! kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
  kind create cluster --name "$CLUSTER_NAME" --config cluster.yml --wait 180s
fi
KUBE_CONTEXT="kind-$CLUSTER_NAME"
kube() { kubectl --context "$KUBE_CONTEXT" "$@"; }

docker build -t todoapp:local ./src
kind load docker-image todoapp:local --name "$CLUSTER_NAME"
kube apply -f .infrastructure/namespace.yml
kube apply -f .infrastructure/secret.yml -f .infrastructure/app-secret.yml
kube apply -f .infrastructure/configMap.yml -f .infrastructure/services.yml
kube apply -f .infrastructure/statefulSet.yml
kube -n mysql rollout status statefulset/mysql --timeout=900s

kube -n todoapp delete job todoapp-migrate --ignore-not-found --wait=true
kube apply -f .infrastructure/migrations.yml
if ! kube -n todoapp wait --for=condition=complete job/todoapp-migrate --timeout=330s; then
  kube -n todoapp logs job/todoapp-migrate --all-containers=true || true
  kube -n todoapp describe job todoapp-migrate
  exit 1
fi

kube apply -f .infrastructure/deployment.yml
kube -n todoapp rollout restart deployment/todoapp
kube apply -f .infrastructure/clusterIp.yml -f .infrastructure/nodeport.yml
kube -n todoapp rollout status deployment/todoapp --timeout=300s
kube -n mysql get pods,pvc
kube -n todoapp get pods,services
printf 'Application: http://localhost:30007\n'
