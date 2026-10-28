{{/*
Deep merge of two maps, `over` wins. Unlike Sprig's merge/mergeOverwrite, an
explicit false, 0 or "" in `over` is kept (Sprig treats them as "unset" and
silently keeps the default). Lists are replaced, not appended.
Returns YAML; use with fromYaml.
*/}}
{{- define "rssb-app.merge" -}}
{{- $out := deepCopy .base -}}
{{- range $k, $v := .over -}}
{{- if and (kindIs "map" $v) (kindIs "map" (get $out $k)) -}}
{{- $_ := set $out $k (include "rssb-app.merge" (dict "base" (get $out $k) "over" $v) | fromYaml) -}}
{{- else -}}
{{- $_ := set $out $k $v -}}
{{- end -}}
{{- end -}}
{{- toYaml $out -}}
{{- end -}}

{{/*
Effective settings of one component: componentDefaults -> typeDefaults.<type> -> the component.
Call with (dict "root" $ "name" $name "comp" $comp); returns YAML.
*/}}
{{- define "rssb-app.component" -}}
{{- $root := .root -}}
{{- if not (hasKey $root.Values.typeDefaults .comp.type) -}}
{{- fail (printf "components.%s.type %q is not one of: %s" .name .comp.type (keys $root.Values.typeDefaults | sortAlpha | join ", ")) -}}
{{- end -}}
{{- $withType := include "rssb-app.merge" (dict "base" $root.Values.componentDefaults "over" (get $root.Values.typeDefaults .comp.type)) | fromYaml -}}
{{- include "rssb-app.merge" (dict "base" $withType "over" .comp) -}}
{{- end -}}

{{- define "rssb-app.partOf" -}}
{{- .Values.partOf | default .Release.Name -}}
{{- end -}}

{{/*
Pod labels. The selector is the short `app: <component>` (selectors are
immutable, so it never changes). No chart version here: it would change the
pod template, and every chart release would restart every pod of every app.
*/}}
{{- define "rssb-app.podLabels" -}}
app: {{ .name }}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/part-of: {{ include "rssb-app.partOf" .root }}
app.kubernetes.io/component: {{ .type }}
{{- end -}}

{{/* Labels on every object: the pod labels plus who rendered it, and which chart version. */}}
{{- define "rssb-app.labels" -}}
{{ include "rssb-app.podLabels" . }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
{{- end -}}

{{- define "rssb-app.image" -}}
{{- printf "%s@%s" .image.repository .image.digest -}}
{{- end -}}

{{/* Restricted Pod Security settings. Not configurable on purpose: platform rule. */}}
{{- define "rssb-app.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "rssb-app.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}

{{/* envFrom: the component's ConfigMap (if it has env) and its Secrets. */}}
{{- define "rssb-app.envFrom" -}}
{{- if .c.env }}
- configMapRef:
    name: {{ .name }}-config
{{- end }}
{{- range .c.secretRefs }}
- secretRef:
    name: {{ . }}
{{- end }}
{{- end -}}

{{/* One emptyDir per writable path: volumes and mounts share the generated names. */}}
{{- define "rssb-app.writableVolumes" -}}
{{- range $i, $p := .writablePaths }}
- name: writable-{{ $i }}
  emptyDir: {}
{{- end }}
{{- end -}}

{{- define "rssb-app.writableMounts" -}}
{{- range $i, $p := .writablePaths }}
- name: writable-{{ $i }}
  mountPath: {{ $p }}
{{- end }}
{{- end -}}

{{/*
Database name: database.name, or the namespace with '-' as '_' (todo-uat ->
todo_uat), which is also the role name. One role and database per product per
environment, like the namespace.
*/}}
{{- define "rssb-app.databaseName" -}}
{{- .c.database.name | default (.root.Release.Namespace | replace "-" "_") -}}
{{- end -}}

{{/*
Environment for a managed database (or another component's, through
existingSecret): the four connection details from the Secret provider-sql
writes, and the URL most Node drivers read, composed from them by Kubernetes
($(VAR) expands earlier entries of the same env list).
*/}}
{{- define "rssb-app.databaseEnv" -}}
{{- if or .c.database.managed .c.database.existingSecret }}
{{- $secret := .c.database.existingSecret | default (printf "%s-db" .name) }}
{{- range $key := list "username" "password" "endpoint" "port" }}
- name: DB_{{ $key | upper }}
  valueFrom:
    secretKeyRef:
      name: {{ $secret }}
      key: {{ $key }}
{{- end }}
- name: {{ .c.database.urlEnv }}
  value: postgresql://$(DB_USERNAME):$(DB_PASSWORD)@$(DB_ENDPOINT):$(DB_PORT)/{{ include "rssb-app.databaseName" (dict "root" .root "c" .c) }}{{ .c.database.urlSuffix }}
{{- end }}
{{- end -}}

{{/*
Kafka topic and group prefix for this environment: kafka.topicPrefix, or
<env>.<product>. from the namespace <product>-<env> (logistics-uat -> uat.logistics.).
*/}}
{{- define "rssb-app.kafkaPrefix" -}}
{{- if .c.kafka.topicPrefix -}}
{{- .c.kafka.topicPrefix -}}
{{- else -}}
{{- $env := .root.Release.Namespace | splitList "-" | last -}}
{{- $product := .root.Release.Namespace | trimSuffix (printf "-%s" $env) -}}
{{- printf "%s.%s." $env $product -}}
{{- end -}}
{{- end -}}

{{/*
Environment for a managed Kafka user (or another component's, through
existingSecret): username, password and brokers from the Secret provider-kafka
writes, plus the prefix the app must put in front of its topics and groups.
*/}}
{{- define "rssb-app.kafkaEnv" -}}
{{- if or .c.kafka.managed .c.kafka.existingSecret }}
{{- $secret := .c.kafka.existingSecret | default (printf "%s-kafka" .name) }}
{{- range $key := list "username" "password" "brokers" }}
- name: KAFKA_{{ $key | upper }}
  valueFrom:
    secretKeyRef:
      name: {{ $secret }}
      key: {{ $key }}
{{- end }}
- name: KAFKA_TOPIC_PREFIX
  value: {{ include "rssb-app.kafkaPrefix" (dict "root" .root "c" .c) | quote }}
{{- end }}
{{- end -}}
