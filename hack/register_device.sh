#! /usr/bin/env bash

function log(){
    echo "register_device.sh: $1" >&2
}

function help(){
    log "execute script as
        ./generate.sh -n CLUSTER_NAME -a MAC_ADDR [-r REPO_URL -g GIT_REF ] 

        -n  the name to be given to the cluster in the ACM hub
        -a  the MAC address associated with the device
        -r  (optional) source repo URL in the format \"git::ssh://git@github.com/\$OWNER/\$REPO//\$SUBDIR\"
                when specifying repo root directory, trim \"//\$SUBDIR\" from the URL
        -g  (optional) git ref within the repository.
    "
}

function apply_cluster_namespace(){
    log "creating namespace \"$CLUSTER_NAME\""
    cat <<EOF | oc apply -f - 1>/dev/null
apiVersion: v1
kind: Namespace
metadata:
    name: $CLUSTER_NAME
EOF
}

function apply_managed_cluster(){
    log "applying managedcluster"
    cat <<EOF | oc apply -f - 1>/dev/null
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: $CLUSTER_NAME
spec:
  hubAcceptsClient: true
EOF
}

function appy_klusterlet_addon_config(){
    log "applying klusterletAddonConfig"
    cat <<EOF | oc apply -f - 1>/dev/null
apiVersion: agent.open-cluster-management.io/v1
kind: KlusterletAddonConfig
metadata:
  name: $CLUSTER_NAME 
  namespace: $CLUSTER_NAME
spec:
  clusterName: $CLUSTER_NAME
  clusterNamespace: $CLUSTER_NAME
  applicationManager:
    enabled: true
  certPolicyController:
    enabled: false
  clusterLabels:
    cloud: auto-detect
    vendor: auto-detect
  iamPolicyController:
    enabled: false
  policyController:
    enabled: false
  searchCollector:
    enabled: true 
  version: 2.0.0
EOF
}

# errors are ignored in the name of idempotency. the most common error is that the object already exists
function deploy_to_hub(){
    apply_cluster_namespace
    apply_managed_cluster
    appy_klusterlet_addon_config
}

function wait_for_managedcluster_import_secret(){
    log "waiting for secret \"$CLUSTER_NAME/$CLUSTER_NAME-import\""
    until oc get secret -n $CLUSTER_NAME "${CLUSTER_NAME}-import" 1>/dev/null; do log "waiting for secret \"$CLUSTER_NAME/$CLUSTER_NAME-import\""; sleep 2; done
}

function extract_import_secret(){
    # Extract the kubeconfig from the secret.  Don't decode it, it has to be passed through the DM as base64.
    local config="$(sed 's/  kubeconfig: //' <(oc get secret -n $CLUSTER_NAME $CLUSTER_NAME-import -o jsonpath={.data.import\\.yaml} | base64 -d | grep 'kubeconfig: '))"
    [ -z "$config" ] && { log "failed to extract import secret from $CLUSTER_NAME $CLUSTER_NAME-import-foo"; return 1;  }
    echo "$config"
}

function dump_import_secret(){    
    local secret="$1"

    cat <<EOF > "$CONFIG_FILE"
blueprint: $REPO 
ref: $GITREF
template:
    kubeconfig: $secret
    clustername: $CLUSTER_NAME
EOF
}

# Send the file to our registry
function register_device(){
    log "registering device $MAC"
    aws s3 cp "$CONFIG_FILE" s3://edge-lab-device-manager || { log "failed to upload to $CONFIG_FILE to s3"; return 1; }
}

# currently unused, since we write to tmp dirs.
function clean_up(){
    log "removing local secret $CONFIG_FILE"
    [[ "$CONFIG_FILE" =~ .*\.yaml$ ]] || { log "refusing to delete file \"$CONFIG_FILE\", something fishy happened"; return 1; }
    rm "$CONFIG_FILE"
}

################ main ###################

CURDIR="$(readlink -f $(dirname $BASH_SOURCE))"

optstring="hg:r:n:a:"
while getopts "$optstring" opt 
do
    case "$opt" in
        g)  
            [[ "$OPTARG" =~ ^-. ]] && { log "-g required argument unset"; exit 1; }
            GITREF="$OPTARG" ;;
        r)  
            [[ "$OPTARG" =~ ^-. ]] && { log "-r required argument unset"; exit 1; }
            REPO="$OPTARG" ;;
        n)  
            [[ "$OPTARG" =~ ^-. ]] && { log "-n required argument unset"; exit 1; }
            CLUSTER_NAME="$OPTARG" ;;
        a)  
            [[ "$OPTARG" =~ ^-. ]] && { log "-a required argument unset"; exit 1; }
            MAC="$OPTARG" ;;
        h)  
            help; exit 0 ;;
        ?)
            exit 1
    esac    
done

[ $OPTIND -eq 1 ] && { log "no options were set.  At a minimun, set -a MAC_ADDR and -n CLUSTER_NAME"; exit 1; }

WORK_DIR="$(readlink -f $(mktemp -d))" || exit 1
CONFIG_FILE="$WORK_DIR/$MAC.yaml"

: ${REPO:=git::ssh://git@github.com/redhat-et/ushift}
: ${GITREF:=o3s}

deploy_to_hub                           || exit 1
wait_for_managedcluster_import_secret   || exit 1
sec=$(extract_import_secret)            || exit 1
dump_import_secret "$sec"               || exit 1
register_device                         || exit 1
