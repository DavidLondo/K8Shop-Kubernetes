{{- define "bookstore.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "bookstore.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "bookstore.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "bookstore.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "bookstore.selectorLabels" -}}
app.kubernetes.io/name: {{ include "bookstore.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "bookstore.labels" -}}
helm.sh/chart: {{ include "bookstore.chart" . }}
{{ include "bookstore.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.commonLabels }}
{{ toYaml . | indent 0 }}
{{- end -}}
{{- end -}}

{{- define "bookstore.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ default (include "bookstore.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
{{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}
