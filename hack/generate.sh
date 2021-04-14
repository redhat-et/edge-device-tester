#! /usr/bin/env bash

function help(){
    echo "execute script as
        ./generate.sh \$MAC_ADDR \$CLUSTER_NAME

        MAC_ADDR: The MAC address associated with the device
        CLUSTER_NAME: The name to be given to the cluster in the ACM hub
    "
}

CURDIR="$(readlink -f $(dirname ${BASH_SOURCE}))"

MAC="$1"
CLUSTER_NAME="$2"

([ -z "$MAC" ] || [ -z "$CLUSTER_NAME" ]) && \
    {
        help
        exit 1
    }

# Prepare the managed cluster namespace
oc create ns $CLUSTER_NAME

# Apply the managed cluster CR
cat <<EOF | oc apply -f -
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: $CLUSTER_NAME
spec:
  hubAcceptsClient: true
EOF

# Lazy wait
sleep 5

# Extract the kubeconfig from the secret.  Don't decode it, it has to be passed through the DM as base64.
CONFIG="$(sed 's/  kubeconfig: //' <(oc get secret -n $CLUSTER_NAME $CLUSTER_NAME-import -o jsonpath={.data.import\\.yaml} | base64 -d | grep 'kubeconfig: '))"


CONFIG_FILE="${CURDIR}/$MAC.yaml"

# Create the file
cat <<EOF > "${CONFIG_FILE}"
blueprint: git::ssh://git@github.com/redhat-et/ushift
ref: o3s
template:
    kubeconfig: $CONFIG
    clustername: $CLUSTER_NAME
EOF

# Send the file to our registry
aws s3 cp "${CONFIG_FILE}" s3://edge-lab-device-manager || \
    {
        echo "failed to upload to $CONFIG_FILE to s3"
        exit 1
    }
