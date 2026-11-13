# Monocle Kubernetes agent

Sends the state, metrics, events and container logs of a Kubernetes cluster to
[Monocle](https://monocle.sh). The chart runs two
[OpenTelemetry Collectors](https://github.com/open-telemetry/opentelemetry-helm-charts):

- `agent`, a DaemonSet. On each node, it reads kubelet metrics and container logs, and forwards
  your services' OTLP data with their pod metadata.
- `cluster`, one replica. It reads the state of the cluster and its events.

## Prerequisites

- Kubernetes 1.33 or later.
- Helm 3.14 or later.
- A cluster key. An organization admin gets it with **Connect a cluster** on Monocle's Kubernetes
  page.

## Install

```bash
helm install monocle-agent oci://ghcr.io/monocle-sh/charts/monocle-k8s-agent \
  -n monocle --create-namespace \
  --set monocle.apiKey=<cluster key> \
  --set-string monocle.clusterName=prod-eu
```

Use the cluster name you gave in Monocle. The cluster appears in Monocle within a few minutes.

To keep the key out of your values, for example with Argo CD or Flux, create the Secret yourself
and set `monocle.createSecret=false`:

```bash
kubectl create namespace monocle
kubectl -n monocle create secret generic monocle-k8s-agent --from-literal=apiKey=<cluster key>
helm upgrade --install monocle-agent oci://ghcr.io/monocle-sh/charts/monocle-k8s-agent \
  -n monocle \
  --set monocle.createSecret=false \
  --set-string monocle.clusterName=prod-eu
```

`global.secret.name` and `global.secret.key` set another Secret name or key.

## Send your services' telemetry through the agent

Point your services' OTLP exporter at the agent, with the headers they send to Monocle. The agent
adds the pod, workload, namespace and node, then forwards each request with its own headers:

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: http://monocle-agent.monocle.svc:4318
  - name: OTEL_EXPORTER_OTLP_HEADERS
    value: x-api-key=<service key>,x-monocle-env=production
```

The Service is named `<release>-agent`, or after the release when its name contains `agent`.

The agent also listens on ports 4317 and 4318 of each node. A service that sends there must set
`k8s.pod.ip` in `OTEL_RESOURCE_ATTRIBUTES`, or its data arrives without pod metadata. To close
these host ports, for example on GKE Autopilot, set `agent.ports.otlp.hostPort=0` and
`agent.ports.otlp-http.hostPort=0`.

## Filter container logs

The agent collects the logs of every container except those in `kube-system`. Each line counts
toward your organization's usage. To filter lines on the node, set `global.logs`:

```yaml
global:
  logs:
    excludeNamespaces: [kube-system, monitoring]
    excludeContainers: [istio-proxy]
    dropPatterns: ["^GET /healthz"]
    minSeverity: info
```

To skip one workload, annotate its pods with `monocle.sh/logs: "false"`.

`minSeverity` reads the level from the first `level`, `lvl` or `severity` field of a JSON or logfmt
line. The agent keeps lines without a level.

The agent stores its position in each log file in `/var/lib/monocle-k8s-agent` on the node, so a
restart loses no lines. A root init container gives the collector that directory.

## Values

| Value                             | Default                     | Description                                                                                             |
| --------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------- |
| `monocle.apiKey`                  | `''`                        | Cluster key. Required unless `monocle.createSecret` is `false`.                                         |
| `monocle.clusterName`             | `''`                        | Name of the cluster in Monocle. Required.                                                               |
| `monocle.endpoint`                | `https://ingest.monocle.sh` | Monocle OTLP/HTTP endpoint.                                                                             |
| `monocle.createSecret`            | `true`                      | Set to `false` to create the Secret yourself.                                                           |
| `global.secret.name`              | `monocle-k8s-agent`         | Name of the Secret that holds the cluster key.                                                          |
| `global.secret.key`               | `apiKey`                    | Key of the cluster key in that Secret.                                                                  |
| `global.logs.excludeNamespaces`   | `[kube-system]`             | Namespaces whose logs are skipped. Setting it replaces the default.                                     |
| `global.logs.includeNamespaces`   | `[]`                        | When set, the only namespaces whose logs are read.                                                      |
| `global.logs.excludePods`         | `[]`                        | Glob patterns on pod names whose logs are skipped.                                                      |
| `global.logs.excludeContainers`   | `[]`                        | Glob patterns on container names whose logs are skipped.                                                |
| `global.logs.dropPatterns`        | `[]`                        | Regular expressions. The agent drops the lines that match.                                              |
| `global.logs.minSeverity`         | `''`                        | Drops lines below `debug`, `info`, `warn`, `error` or `fatal`.                                          |
| `global.logs.multiline`           | `true`                      | Joins the lines of a stack trace into one record.                                                       |
| `global.metrics.prometheusScrape` | `false`                     | Scrapes pods annotated `prometheus.io/scrape: "true"` every 60 seconds, up to 10,000 series per scrape. |
| `agent.enabled`                   | `true`                      | Deploys the node agent.                                                                                 |
| `cluster.enabled`                 | `true`                      | Deploys the cluster collector.                                                                          |

`agent` and `cluster` also accept every value of the upstream
[opentelemetry-collector chart](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-collector),
such as `resources` or `nodeSelector`.

On kind or minikube, also set `agent.config.receivers.kubeletstats.insecure_skip_verify=true`.

## Replace the key

In Monocle, open the Kubernetes tab of the organization settings and click **New key…** in the menu
of the cluster. The old key stops working within 5 minutes. Put the new key in `monocle.apiKey`
or in your Secret, then restart the collectors:

```bash
kubectl -n monocle rollout restart daemonset/monocle-agent-agent deployment/monocle-agent-cluster
```

## Upgrade and uninstall

```bash
helm upgrade monocle-agent oci://ghcr.io/monocle-sh/charts/monocle-k8s-agent -n monocle --reset-then-reuse-values
helm uninstall monocle-agent -n monocle
```

`--reset-then-reuse-values` keeps your values and adds the defaults of the new version.
`--reuse-values` fails when a new version adds values.
