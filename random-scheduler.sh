#!/bin/sh

KUBE_API_URL=https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT_HTTPS/api
KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CA_CERT_FILE=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
AUTH_HEADER="Authorization: Bearer $KUBE_TOKEN"

# kubernetesのAPIを叩く
function callK8sApi {
  METHOD="$1"
  ENDPOINT="${2##/}"
  shift
  shift

  URL="$KUBE_API_URL/$ENDPOINT"
  CURL_OPTS="-s --cacert '$CA_CERT_FILE' -H '$AUTH_HEADER' "

  if [ "$METHOD" == "GET" ]; then
    CURL_OPTS="$CURL_OPTS -G"

    for param in "$@"; do
      CURL_OPTS="$CURL_OPTS --data-urlencode '$param'"
    done
  elif [ "$METHOD" == "POST" ]; then
    CURL_OPTS="$CURL_OPTS -H 'Content-Type: application/json'"
    for param in "$@"; do
      CURL_OPTS="$CURL_OPTS -d '$param' "
    done
  fi

  cmd="curl $CURL_OPTS '$URL'"
  echo "cmd: $cmd" >&2
  echo "$(eval $cmd)"
}

# ノード一覧を取得し、名前を取り出してランダムに1つ抽出する
function getRandomNode {
  echo "$(callK8sApi "GET" "/v1/nodes" |  jq -r '.items[].metadata.name' | shuf -n 1)"
}

# NodeNameが入っていない(アサインされていない)かつスケジューラの名前がrandom-schedulerのPodを取り出す
function getUnassignedPods {
  echo "$(callK8sApi "GET" "/v1/pods" "fieldSelector=spec.nodeName=" "fieldSelector=spec.schedulerName=random-scheduler" | jq -r '.items[].metadata | .namespace + "\t" + .name')"
}

function assignPodToNode {
  NAMESPACE=$1
  POD=$2
  NODE=$3

  JSONBODY=$(cat <<JSON
  {
    "apiVersion": "v1",
    "kind": "Binding",
    "metadata": {
      "name": "$POD"
    },
    "target": {
      "apiVersion": "v1",
      "kind": "Node",
      "name": "$NODE"
    }
  }
JSON
  )

  echo "$(callK8sApi "POST" "/v1/namespaces/$NAMESPACE/pods/$POD/binding" "$JSONBODY")"
}

function main {

  while true; do
    # 未アサインのpod取得
    PODS=$(getUnassignedPods)

    # podがなければスリープして再取得
    if [ -z "$PODS" ]; then
      sleep 1
      continue
    fi

    # podがあるときは1つずつノードをランダムに選んで配置していく
    local IFS=$'\n'
    for POD in $PODS; do
      NODE=$(getRandomNode)
      NAMESPACE=$(echo $POD | cut -f 1)
      PODNAME=$(echo $POD | cut -f 2)

      echo "'${NAMESPACE}:${PODNAME}' -> '$NODE'"

      # PodをNodeにアサインする
      assignPodToNode "$NAMESPACE" "$PODNAME" "$NODE"
    done

    sleep 1
  done
}

main
