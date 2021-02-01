#!/usr/bin/env bash

STATE_DIR="${STATE_DIR:-${HOME}/.cluster}"
PULL_SECRET_FILE="${PULL_SECRET_FILE:-${HOME}/.pull-secret.json}"
SSH_PUB_KEY_FILE="${SSH_PUB_KEY_FILE:-${STATE_DIR}/id_rsa.pub}"

mkdir -p "${STATE_DIR}" >/dev/null

if [ ! -f "${SSH_PUB_KEY_FILE}" ]; then
  ssh-keygen -t rsa -b 4096 -C "edge@lab" -N '' -f "${SSH_PUB_KEY_FILE%.pub}"
fi

cat <<-EOF > "${STATE_DIR}/install-config.yaml"
apiVersion: v1
baseDomain: aws.octo.edge-sites.net
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      type: m5.xlarge
  replicas: 3
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
metadata:
  creationTimestamp: null
  name: edge-lab
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: us-east-2
publish: External
pullSecret: '$(cat "${PULL_SECRET_FILE}")'
sshKey: |
  $(cat "${SSH_PUB_KEY_FILE}")
EOF
cp "${STATE_DIR}/install-config.yaml" "${STATE_DIR}/install-config.yaml.bak"

openshift-install create cluster --dir="${STATE_DIR}" --log-level=debug
