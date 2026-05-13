terraform {
  backend "gcs" {
    # Partial config — bucket and prefix are passed via -backend-config in CI and local runs:
    #   tofu init \
    #     -backend-config="bucket=<GCP_PROJECT_ID>-computer_vision_yolo" \
    #     -backend-config="prefix=opentofu/state/dev"
    #
    # The state is stored in the existing dataset bucket under a separate prefix,
    # so it persists across CI runs and local invocations.
  }
}
