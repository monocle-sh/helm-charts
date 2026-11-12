<img width="1500" height="500" alt="Monocle" src="https://github.com/user-attachments/assets/45d9a45e-2b49-40c3-86af-1fe3ce26858d" />

# Monocle Helm charts

Helm charts to send telemetry from your infrastructure to [Monocle](https://monocle.sh).

| Chart                                           | Description                                                                                                                                                                        |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`monocle-k8s-agent`](charts/monocle-k8s-agent) | Kubernetes monitoring: cluster state, kubelet metrics, Kubernetes events and container logs, and an OTLP endpoint on each node that adds pod metadata to your services' telemetry. |

Charts are published as OCI artifacts on GitHub Container Registry, so there is no `helm repo add`
step:

```bash
helm install monocle-agent oci://ghcr.io/monocle-sh/charts/monocle-k8s-agent \
  -n monocle --create-namespace \
  --set monocle.apiKey=<ingestion key> \
  --set monocle.environment=production \
  --set monocle.clusterName=prod-eu
```

See each chart's README for its requirements and values.

## Release

Bump `version` in the chart's `Chart.yaml` and merge the change to `main`. The `Release` workflow
publishes every chart whose version is not released yet to `oci://ghcr.io/monocle-sh/charts/<chart>`,
then tags the commit `<chart>-<version>` and creates a GitHub release with the packaged chart.
Changes merged without a version bump wait for the next one.

## License

[ISC](LICENSE)
