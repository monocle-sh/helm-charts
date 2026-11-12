# Monocle Kubernetes agent

Kubernetes monitoring for [Monocle](https://monocle.sh). The chart runs two
[OpenTelemetry Collectors](https://github.com/open-telemetry/opentelemetry-helm-charts):

- `agent`, a DaemonSet: kubelet metrics of nodes, pods and volumes, container logs, and an OTLP
  endpoint for your services. It adds the pod, workload, namespace and node to the traces, logs and
  metrics they send, then forwards them to Monocle with their own API key.
- `cluster`, one replica: the state of deployments, pods, jobs and nodes, and Kubernetes events.

## Prerequisites

- Kubernetes 1.33 or later. The agent reads pod specs from the kubelet with the `nodes/pods`
  permission, which older versions do not check.
- Helm 3.8 or later, for OCI charts.
- A Monocle ingestion API key and the slug of the environment the cluster belongs to.

## Install

```bash
helm install monocle-agent oci://ghcr.io/monocle-sh/charts/monocle-k8s-agent \
  -n monocle --create-namespace \
  --set monocle.apiKey=<ingestion key> \
  --set monocle.environment=production \
  --set monocle.clusterName=prod-eu
```

Use one `clusterName` per cluster. Cluster state, metrics, events and logs appear in Monocle within
a few minutes.

### Keep the API key out of Helm values

To create the Secret yourself, for example from a secret manager, create `monocle-k8s-agent` in the
release namespace before installing, and set `monocle.createSecret=false`:

```bash
kubectl -n monocle create secret generic monocle-k8s-agent \
  --from-literal=apiKey=<ingestion key> \
  --from-literal=environment=production \
  --from-literal=endpoint=https://ingest.monocle.sh \
  --from-literal=clusterName=prod-eu
helm install monocle-agent oci://ghcr.io/monocle-sh/charts/monocle-k8s-agent \
  -n monocle --set monocle.createSecret=false
```

## Send your services' telemetry through the agent

Point your services' OTLP exporter at the agent Service, with the same API key and environment
headers they would send to Monocle directly. The Service keeps traffic on the sender's node
(`internalTrafficPolicy: Local`), so the agent sees which pod sent it. It is named after the
release: `<release>-agent`, or the release name itself when it already contains `agent`, as
`monocle-agent` does:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: http://monocle-agent.monocle.svc:4318
  - name: OTEL_EXPORTER_OTLP_HEADERS
    value: x-api-key=<service key>,x-monocle-env=production
```

The agent forwards only the headers a request carries: a request without `x-api-key` is refused by
Monocle, never sent with the cluster's key.

The agent also listens on ports 4317/4318 of each node. That path often hides the sender's address,
so a service that uses it must send its pod IP for the agent to recognize it:

```yaml
env:
  - name: HOST_IP
    valueFrom: { fieldRef: { fieldPath: status.hostIP } }
  - name: POD_IP
    valueFrom: { fieldRef: { fieldPath: status.podIP } }
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: http://$(HOST_IP):4318
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: k8s.pod.ip=$(POD_IP)
```

Where host ports are refused or taken, such as on GKE Autopilot, under a Pod Security or Kyverno
policy that forbids them, or when another agent holds 4317/4318, close them:

```bash
--set agent.ports.otlp.hostPort=null --set agent.ports.otlp-http.hostPort=null
```

Either way, a node whose agent is not running drops its services' telemetry until the agent is back.

## Values

| Value                  | Default                     | Description                                                                      |
| ---------------------- | --------------------------- | -------------------------------------------------------------------------------- |
| `monocle.apiKey`       | `''`                        | Ingestion API key. Required unless `monocle.createSecret` is `false`.            |
| `monocle.environment`  | `''`                        | Environment slug of the cluster's own telemetry, such as `production`. Required. |
| `monocle.clusterName`  | `''`                        | Name shown in Monocle, one per cluster. Required.                                |
| `monocle.endpoint`     | `https://ingest.monocle.sh` | Monocle OTLP/HTTP endpoint.                                                      |
| `monocle.createSecret` | `true`                      | Set to `false` to provide the `monocle-k8s-agent` Secret yourself.               |
| `agent.enabled`        | `true`                      | Deploys the node agent DaemonSet.                                                |
| `cluster.enabled`      | `true`                      | Deploys the cluster collector.                                                   |

`agent` and `cluster` accept every value of the upstream
[opentelemetry-collector chart](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-collector),
such as `resources`, `tolerations`, `nodeSelector` or `priorityClassName`. The agent tolerates every
taint by default, so it also runs on control-plane nodes. See [values.yaml](values.yaml) for the
collector configuration.

Clusters whose kubelets use self-signed certificates without IP SANs, such as kind or minikube, also
need `--set agent.config.receivers.kubeletstats.insecure_skip_verify=true`.

## Rotate the API key

The collectors read the Secret when they start, so restart them after changing the key, before you
revoke the old one:

```bash
kubectl -n monocle rollout restart daemonset/monocle-agent-agent deployment/monocle-agent-cluster
```

## Upgrade and uninstall

```bash
helm upgrade monocle-agent oci://ghcr.io/monocle-sh/charts/monocle-k8s-agent -n monocle --reuse-values
helm uninstall monocle-agent -n monocle
```
