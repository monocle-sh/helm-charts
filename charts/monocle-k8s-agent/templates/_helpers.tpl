{{- /*
These helpers read `global`, the only values the parent chart shares with the agent and cluster
subcharts. The subcharts call them from `extraEnvs`, which they render with `tpl`, so a change
to these options changes the pod spec and restarts the collectors.
*/ -}}

{{- define "monocle-k8s-agent.secretName" -}}
{{- .Values.global.secret.name | default "monocle-k8s-agent" -}}
{{- end }}

{{- define "monocle-k8s-agent.secretKey" -}}
{{- .Values.global.secret.key | default "apiKey" -}}
{{- end }}

{{- /* Log files to read, as a JSON list. Paths are /var/log/pods/<namespace>_<pod>_<uid>/<container>/*.log. */ -}}
{{- define "monocle-k8s-agent.logs.include" -}}
{{- $paths := list -}}
{{- range .Values.global.logs.includeNamespaces -}}
{{- $paths = append $paths (printf "/var/log/pods/%s_*/*/*.log" .) -}}
{{- end -}}
{{- toJson (default (list "/var/log/pods/*/*/*.log") $paths) -}}
{{- end }}

{{- /* Log files to skip, as a JSON list. The agent's own logs come first, as in the upstream preset. */ -}}
{{- define "monocle-k8s-agent.logs.exclude" -}}
{{- $logs := .Values.global.logs -}}
{{- $paths := list (printf "/var/log/pods/%s_%s*_*/%s/*.log" (include "opentelemetry-collector.namespace" .) (include "opentelemetry-collector.fullname" .) (include "opentelemetry-collector.lowercase_chartname" .)) -}}
{{- range $logs.excludeNamespaces -}}
{{- $paths = append $paths (printf "/var/log/pods/%s_*/*/*.log" .) -}}
{{- end -}}
{{- range $logs.excludePods -}}
{{- $paths = append $paths (printf "/var/log/pods/*_%s_*/*/*.log" .) -}}
{{- end -}}
{{- range $logs.excludeContainers -}}
{{- $paths = append $paths (printf "/var/log/pods/*/%s/*.log" .) -}}
{{- end -}}
{{- toJson $paths -}}
{{- end }}

{{- /*
OTTL conditions of the log lines to drop, as a JSON list. It is rendered inside a single-quoted
YAML string, so single quotes are doubled, and the collector expands `${...}` in it, so `$` is
doubled too. Lines below `minSeverity` take their level from the `severity` operator of `file_log`.
*/ -}}
{{- define "monocle-k8s-agent.logs.drop" -}}
{{- $logs := .Values.global.logs -}}
{{- $conditions := list `resource.attributes["monocle.logs"] == "false"` -}}
{{- range $logs.dropPatterns -}}
{{- /* An invalid pattern fails the install here instead of crash-looping the agent on every node. */ -}}
{{- $_ := mustRegexMatch . "" -}}
{{- $conditions = append $conditions (printf "IsMatch(log.body, %s)" (toJson .)) -}}
{{- end -}}
{{- with $logs.minSeverity -}}
{{- if not (has . (list "debug" "info" "warn" "error" "fatal")) -}}
{{- fail (printf "global.logs.minSeverity must be debug, info, warn, error or fatal, not %q" .) -}}
{{- end -}}
{{- $conditions = append $conditions (printf "log.severity_number != SEVERITY_NUMBER_UNSPECIFIED and log.severity_number < SEVERITY_NUMBER_%s" (upper .)) -}}
{{- end -}}
{{- toJson $conditions | replace "$" "$$" | replace "'" "''" -}}
{{- end }}
