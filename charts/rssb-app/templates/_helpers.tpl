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
Labels on every object. The selector stays the short `app: <component>`:
selectors are immutable, and the Kustomize manifests this chart replaces used it.
*/}}
{{- define "rssb-app.labels" -}}
app: {{ .name }}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/part-of: {{ include "rssb-app.partOf" .root }}
app.kubernetes.io/component: {{ .type }}
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
