#!/usr/bin/env bash

REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
podman login -u $(oc whoami | sed 's/://') -p $(oc whoami -t) --tls-verify=false ${REGISTRY}

IMAGES=$(find images/* -type d | xargs) 
for i in ${IMAGES}; do
    podman push --tls-verify=false ${REGISTRY}/edt/$(basename ${i}):latest
done
