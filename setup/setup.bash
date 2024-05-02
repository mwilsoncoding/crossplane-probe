#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

export KUBECONFIG=${HOME}/.kube/crossplane-probe-kind-config
echo "export KUBECONFIG=${KUBECONFIG}" >.env

gum style \
  --foreground 212 --border-foreground 212 --border double \
  --margin "1 2" --padding "2 4" \
  'Setup for crossplane experimentation'

echo "
## You will need following tools installed:
|Name            |Required             |More info                                          |
|----------------|---------------------|---------------------------------------------------|
|Linux Shell     |Yes                  |Use WSL if you are running Windows                 |
|Docker          |Yes                  |'https://docs.docker.com/engine/install'           |
|kind CLI        |Yes                  |'https://kind.sigs.k8s.io/docs/user/quick-start/#installation'|
|kubectl CLI     |Yes                  |'https://kubernetes.io/docs/tasks/tools/#kubectl'  |
|crossplane CLI  |Yes                  |'https://docs.crossplane.io/latest/cli'            |
|yq CLI          |Yes                  |'https://github.com/mikefarah/yq#install'          |
|envsubst CLI    |Yes                  |'https://github.com/a8m/envsubst/releases/'        |
|Google Cloud account with admin permissions|If using Google Cloud|'https://cloud.google.com'|
|Google Cloud CLI|If using Google Cloud|'https://cloud.google.com/sdk/docs/install'        |
|AWS account with admin permissions|If using AWS|'https://aws.amazon.com'                  |
|AWS CLI         |If using AWS         |'https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html'|
|Azure account with admin permissions|If using Azure|'https://azure.microsoft.com'         |
|az CLI          |If using Azure       |'https://learn.microsoft.com/cli/azure/install-azure-cli'|

If you are running this script from **Nix shell**, most of the requirements are already set with the exception of **Docker** and the **hyperscaler account**.
" | gum format

gum confirm "
Do you have those tools installed?
" || exit 0

kind create cluster --config kind.yaml --wait 5m

# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Give helm access to crossplane
helm repo add \
  crossplane-stable https://charts.crossplane.io/stable

helm repo update

TMPDIR=$(mktemp -d)

helm pull crossplane-stable/crossplane --untar --destination $TMPDIR

if ! [ -d ./crossplane/helm/crossplane ] ||
  ( ! diff -r ${TMPDIR}/crossplane ./crossplane/helm/crossplane &&
    gum confirm --default=No '
    The local helm chart differs from the one pulled from the repo.
    Overwrite existing chart for crossplane?
  ' ) ; then
  rm -rf ./crossplane/helm/crossplane
  mv ${TMPDIR}/crossplane ./crossplane/helm/crossplane
fi

helm upgrade --install crossplane ./crossplane/helm/crossplane \
  --namespace crossplane-system --create-namespace --wait

export SQL_XRD_VERSION=v3
echo "export SQL_XRD_VERSION=${SQL_XRD_VERSION}" >>.env

kubectl apply \
  --filename providers/sql-${SQL_XRD_VERSION}.yaml

gum spin --spinner dot \
  --show-output \
  --title "Waiting for Crossplane providers..." -- \
kubectl wait \
  --for=condition=healthy provider.pkg.crossplane.io \
  --all \
  --timeout=1800s

kubectl apply \
  --filename compositions/sql-${SQL_XRD_VERSION}/definition.yaml

gum spin --spinner dot -- \
sleep 5

kubectl apply \
  --filename compositions/sql-${SQL_XRD_VERSION}/gcp.yaml

# gum spin --spinner dot \
#   --show-output \
#   --title "Waiting for NGINX deployments..." -- \
# kubectl wait \
#   --namespace ingress-nginx \
#   --for=condition=ready pod \
#   --selector=app.kubernetes.io/component=controller \
#   --timeout=90s

gcloud auth login

export PROJECT_ID=crossplane-probe

echo "export PROJECT_ID=${PROJECT_ID}" >>.env

# gcloud projects create ${PROJECT_ID}

# echo 'Select a billing account for linking...'
# 
# BILLING_ACCOUNT_ID=$(gcloud billing accounts list | gum table | cut -d' ' -f1)
# 
# gum confirm "
# Link to billing account ID: ${BILLING_ACCOUNT_ID}?
# " || exit 0
# 
# gcloud billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT_ID}

# gcloud services enable container.googleapis.com \
#   --project $PROJECT_ID
# gcloud services enable sqladmin.googleapis.com \
#   --project $PROJECT_ID
# gcloud services enable servicenetworking.googleapis.com \
#   --project $PROJECT_ID
# gcloud services enable cloudresourcemanager.googleapis.com \
#   --project $PROJECT_ID
# gcloud services enable networkmanagement.googleapis.com \
#   --project $PROJECT_ID
# gcloud services enable iap.googleapis.com \
#   --project $PROJECT_ID
 
export SA_NAME=crossplane-probe
echo "export SA_NAME=${SA_NAME}" >>.env

export SA="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "export SA=${SA}" >>.env

# gcloud iam service-accounts create $SA_NAME \
#   --project $PROJECT_ID
  
export ROLE=roles/admin
echo "export ROLE=${ROLE}" >>.env
  
# gcloud projects add-iam-policy-binding $PROJECT_ID \
#   --role $ROLE \
#   --member serviceAccount:$SA
# 
# gcloud iam service-accounts keys create gcp-creds.json \
#   --project $PROJECT_ID --iam-account $SA

kubectl --namespace crossplane-system \
  create secret generic gcp-creds \
  --from-file creds=./gcp-creds.json

envsubst -i provider-configs/gcp-config.yaml | kubectl apply --filename -

helm pull argo-cd --repo https://argoproj.github.io/argo-helm --untar --destination $TMPDIR

if ! [ -d ./argocd/helm/argocd ] ||
  ( ! diff -r ${TMPDIR}/argo-cd ./argocd/helm/argocd &&
    gum confirm --default=No '
    The local helm chart differs from the one pulled from the repo.
    Overwrite existing chart for argocd?
  ' ) ; then
  rm -rf ./argocd/helm/argocd
  mv ${TMPDIR}/argo-cd ./argocd/helm/argocd
fi

kubectl create namespace a-team

helm upgrade --install argocd ./argocd/helm/argocd \
  --values argocd/helm-values.yaml \
  --namespace argocd \
  --create-namespace \
  --wait

kubectl apply --filename argocd/apps.yaml

# gum spin --spinner dot \
#   --show-output \
#   --title "Waiting for a-team application..." -- \
# kubectl wait \
#   --for=condition=healthy application/a-team \
#   --namespace argocd \
#   --timeout=1800s

gum spin --spinner dot \
  --show-output \
  --title "Waiting 30 seconds to deploy app..." -- \
sleep 30

cat >a-team/managed-resources.yaml \
  managed-resources/gcp-*.yaml 

cat >a-team/composite-resources.yaml \
  composite-resources/gcp-sql-${SQL_XRD_VERSION}.yaml

git add a-team
git commit -m 'ops: deploying demo'
git push

echo '##################'
echo '# Setup complete #'
echo '##################'
echo ''
echo "ArgoCD admin password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
