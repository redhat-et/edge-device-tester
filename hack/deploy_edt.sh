#!/usr/bin/env bash

STATE_DIR="${STATE_DIR:-${HOME}/.cluster}"
SSH_KEY_PAIR="${SSH_KEY_PAIR:-${STATE_DIR}/id_rsa}"
AWS_CREDS_DIR="${AWS_CREDS_DIR:-${STATE_DIR}/.aws}"

base64encode="base64 -w0"
test "$(uname -s)" = "Darwin" && base64encode="base64 -b0"

if [ ! -f "${SSH_KEY_PAIR}" ]; then
  echo "Cannot find SSH key pair ${SSH_KEY_PAIR}"
  exit 1
fi

echo "Creating secret v1/Secret/edt/github-creds from SSH private key ${SSH_KEY_PAIR}"
cat <<-EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: github-creds
  namespace: edt
  annotations:
    tekton.dev/git-0: github.com
type: kubernetes.io/ssh-auth
data:
  ssh-privatekey: >-
    $(cat "${SSH_KEY_PAIR}" | $base64encode)
  ssh-publickey: >-
    $(cat "${SSH_KEY_PAIR}.pub" | $base64encode)
EOF

echo "Creating secret v1/Secret/edt/vm-ssh-keys from SSH pub/priv key pair ${SSH_KEY_PAIR}{,.pub}"
cat <<-EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: vm-ssh-keys
  namespace: edt
  annotations:
    tekton.dev/git-0: github.com
type: kubernetes.io/ssh-auth
data:
  ssh-privatekey: >-
    $(cat "${SSH_KEY_PAIR}" | $base64encode)
  ssh-publickey: >-
    $(cat "${SSH_KEY_PAIR}.pub" | $base64encode)
EOF


if [ ! -d "${AWS_CREDS_DIR}" ]; then
  echo "Cannot find AWS creds dir ${AWS_CREDS_DIR}"
  exit 1
fi

# Note: This secret must embed the actual files from .aws, not just the cred-
# entials, as it'll be used as secret volume for the AWS CLI.
echo "Creating secret v1/Secret/edt/aws-creds from credentials in ${AWS_CREDS_DIR}"
cat <<-EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: aws-creds
  namespace: edt
type: Opaque
data:
  credentials: >-
    $(cat "${AWS_CREDS_DIR}/credentials" | $base64encode)
  config: >-
    $(cat "${AWS_CREDS_DIR}/config" | $base64encode)
EOF

echo "Applying kustomizations in $PWD/kustomizations.yaml"
oc apply -k .