#!/usr/bin/env bash

K3S_SSH_USER=${K3S_SSH_USER:-summit}

if [ -z $K3S_IP ]; then
  echo "What is the IP?"
  read K3S_IP
fi

if [ -z $K3S_CONTEXT ]; then
  echo "What is the Context?"
  read K3S_CONTEXT
fi

main() {
  #k3sup install \
  #  --ip ${K3S_IP} \
  #  --context ${K3S_CONTEXT} \
  #  --merge \
  #  --local-path ~/.kube/config \
  #  --user ${K3S_SSH_USER} \
  #  --k3s-extra-args '--disable traefik --disable servicelb'

  flux bootstrap github \
  --owner=kusold \
  --repository=rockymtn \
  --branch=main \
	--context=${K3S_CONTEXT} \
  --path=k8s/clusters/${K3S_CONTEXT} \
  --personal \
  --private
#  --reconcile
}

main
