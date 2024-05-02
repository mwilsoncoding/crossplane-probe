#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

gum style \
  --foreground 212 --border-foreground 212 --border double \
  --margin "1 2" --padding "2 4" \
  'Tear down crossplane experimentation'

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

source .env

rm -f \
  a-team/managed-resources.yaml \
  a-team/composite-resources.yaml

touch \
  a-team/managed-resources.yaml \
  a-team/composite-resources.yaml

git add a-team

git commit -m "ops: delete demo"

git push

COUNTER=$(kubectl get managed --no-headers | wc -l)

while [ $COUNTER -ne 0 ]; do
  echo "$COUNTER resources still exist. Waiting for them to be deleted..."
  sleep 30
  COUNTER=$(kubectl get managed --no-headers | wc -l)
done


# gcloud projects remove-iam-policy-binding $PROJECT_ID \
#   --role $ROLE \
#   --member serviceAccount:$SA
#
# gcloud iam service-accounts delete $SA_NAME \
#   --project $PROJECT_ID

# gcloud projects delete $PROJECT_ID --quiet

kind delete cluster
