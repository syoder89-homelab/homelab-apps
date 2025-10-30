#!/bin/sh

APP_DIR=../../applications/kargo-config
helm dependency update ${APP_DIR}
kubectl create namespace homelab-apps
helm template -n homelab-apps kargo-config ${APP_DIR} \
  | kubectl apply -f -

kubectl apply -f manifests/
