{ pkgs ? import <nixpkgs> {},
  unstable ? import <nixos-unstable> {}
}:
  pkgs.mkShell {
    nativeBuildInputs = with pkgs; [
      envsubst
      gh
      (google-cloud-sdk.withExtraComponents [google-cloud-sdk.components.gke-gcloud-auth-plugin])
      gum
      jq
      kind
      kubectl
      kubernetes-helm
      unstable.crossplane-cli
      yq
    ];
}
