{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    nativeBuildInputs = with pkgs; [
      crossplane
      envsubst
      gh
      (google-cloud-sdk.withExtraComponents [google-cloud-sdk.components.gke-gcloud-auth-plugin])
      gum
      kind
      kubectl
      kubernetes-helm
      yq
    ];
}
