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
- The key of the cluster: on Monocle's Kubernetes page, an organization admin connects the
  cluster and gets this command with its key filled in.

## Install

```bash
helm install monocle-agent oci://ghcr.io/monocle-sh/charts/monocle-k8s-agent \
  -n monocle --create-namespace \
  --set monocle.apiKey=<cluster key> \
  --set-string monocle.clusterName=prod-eu
```

Use the name the cluster was connected with. Its data belongs to the organization, not to a
project or an environment: admins and members with access to every project see it. Cluster state,
metrics, events and logs appear in Monocle within a few minutes.

### Keep the API key out of Helm values

With Argo CD, Flux or any values file kept in Git, keep the key in a Secret you create yourself:
with kubectl, or synced from a secret manager by a tool such as External Secrets or Sealed
Secrets. Create `monocle-k8s-agent` in the release namespace with the key under `apiKey`, then
install with `monocle.createSecret=false`. To use another Secret name or key, set
`global.secret.name` and `global.secret.key`. The cluster name stays in the values:

```bash
kubectl create namespace monocle
kubectl -n monocle create secret generic monocle-k8s-agent --from-literal=apiKey=<cluster key>
helm upgrade --install monocle-agent oci://ghcr.io/monocle-sh/charts/monocle-k8s-agent \
  -n monocle \
  --set monocle.createSecret=false \
  --set-string monocle.clusterName=prod-eu
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
--set agent.ports.otlp.hostPort=0 --set agent.ports.otlp-http.hostPort=0
```

Either way, a node whose agent is not running drops its services' telemetry until the agent is back.

## Choose which container logs reach Monocle

The agent reads the logs of every container on its node, except in `kube-system`. Each line it
sends counts toward your organization's telemetry usage. These values filter logs on the node,
before they leave the cluster:

```yaml
global:
  logs:
    excludeNamespaces: [kube-system, monitoring]
    excludePods: [load-test-*]
    excludeContainers: [istio-proxy, linkerd-proxy]
    dropPatterns: ["^GET /healthz", "^GET /readyz"]
    minSeverity: info
```

- `excludeNamespaces` replaces the default list. Keep `kube-system` in it to keep skipping that
  namespace.
- `includeNamespaces` reads only the namespaces it lists. `excludeNamespaces` still applies, so
  remove `kube-system` from it to read that namespace.
- `excludePods` and `excludeContainers` take glob patterns on the pod or container name.
- `dropPatterns` takes regular expressions. The agent drops each line that matches one of them.
- `minSeverity` drops lines below a level: `debug`, `info`, `warn`, `error` or `fatal`. Container
  runtimes record no level, so the agent reads it from the first `level`, `lvl` or `severity` field
  of a JSON or logfmt line, and Monocle shows that level. The agent keeps a line whose level it
  cannot find.

To stop collecting the logs of one workload, annotate its pods with the value `"false"`. The agent
skips them at its next read, without an upgrade:

```yaml
metadata:
  annotations:
    monocle.sh/logs: "false"
```

The agent joins the lines of a stack trace into one log record: indented lines, `Caused by:` and
`... N more` attach to the line above them. Set `global.logs.multiline=false` to send each line
as written.

The agent stores how far it has read each log file in `/var/lib/monocle-k8s-agent` on the node. A
restarted or upgraded agent resumes from there, so it sends the lines written while it was down.
An init container, the only part that runs as root, gives the agent's user that directory.

## Values

| Value                           | Default                     | Description                                                            |
| ------------------------------- | --------------------------- | ---------------------------------------------------------------------- |
| `monocle.apiKey`                | `''`                        | Key of the cluster. Required unless `monocle.createSecret` is `false`. |
| `monocle.clusterName`           | `''`                        | Name of the cluster in Monocle. Required.                              |
| `monocle.endpoint`              | `https://ingest.monocle.sh` | Monocle OTLP/HTTP endpoint.                                            |
| `monocle.createSecret`          | `true`                      | Set to `false` to provide the Secret yourself.                         |
| `global.secret.name`            | `monocle-k8s-agent`         | Name of the Secret that holds the cluster key.                         |
| `global.secret.key`             | `apiKey`                    | Key of the cluster key in that Secret.                                 |
| `global.logs.excludeNamespaces` | `[kube-system]`             | Namespaces whose container logs are skipped.                           |
| `global.logs.includeNamespaces` | `[]`                        | When set, the only namespaces whose container logs are read.           |
| `global.logs.excludePods`       | `[]`                        | Glob patterns on pod names whose logs are skipped.                     |
| `global.logs.excludeContainers` | `[]`                        | Glob patterns on container names whose logs are skipped.               |
| `global.logs.dropPatterns`      | `[]`                        | Regular expressions. The agent drops the log lines that match.         |
| `global.logs.minSeverity`       | `''`                        | Drops log lines below `debug`, `info`, `warn`, `error` or `fatal`.     |
| `global.logs.multiline`         | `true`                      | Joins the lines of a stack trace into one log record.                  |
| `agent.enabled`                 | `true`                      | Deploys the node agent DaemonSet.                                      |
| `cluster.enabled`               | `true`                      | Deploys the cluster collector.                                         |

`agent` and `cluster` accept every value of the upstream
[opentelemetry-collector chart](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-collector),
such as `resources`, `tolerations`, `nodeSelector` or `priorityClassName`. The agent tolerates every
taint by default, so it also runs on control-plane nodes. See [values.yaml](values.yaml) for the
collector configuration.

Clusters whose kubelets use self-signed certificates without IP SANs, such as kind or minikube, also
need `--set agent.config.receivers.kubeletstats.insecure_skip_verify=true`.

## Replace the API key

On Monocle, click **New key…** in the menu of the cluster, in the Kubernetes tab of the
organization settings. The old key stops working within 5 minutes. Put the new key in
`monocle.apiKey`, or in the Secret that holds it, then restart the collectors, which read it
only when they start:

```bash
kubectl -n monocle rollout restart daemonset/monocle-agent-agent deployment/monocle-agent-cluster
```

## Upgrade and uninstall

```bash
helm upgrade monocle-agent oci://ghcr.io/monocle-sh/charts/monocle-k8s-agent -n monocle --reset-then-reuse-values
helm uninstall monocle-agent -n monocle
```

`--reset-then-reuse-values` keeps the values you set and takes the defaults of the new version. It
needs Helm 3.14 or later. `--reuse-values` keeps the defaults of the installed version instead, and
the upgrade fails when the new version adds values.
