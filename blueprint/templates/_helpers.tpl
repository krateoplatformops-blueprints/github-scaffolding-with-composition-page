{{/*
Expand the name of the chart.
*/}}
{{- define "frontend-github-scaffolding.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "frontend-github-scaffolding.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "frontend-github-scaffolding.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "frontend-github-scaffolding.labels" -}}
helm.sh/chart: {{ include "frontend-github-scaffolding.chart" . }}
{{ include "frontend-github-scaffolding.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "frontend-github-scaffolding.selectorLabels" -}}
app.kubernetes.io/name: {{ include "frontend-github-scaffolding.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "frontend-github-scaffolding.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "frontend-github-scaffolding.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Compose toRepo URL
*/}}
{{- define "frontend-github-scaffolding.toRepoUrl" -}}
{{- printf "%s/%s/%s" .Values.git.toRepo.scmUrl .Values.git.toRepo.org .Values.git.toRepo.name }}
{{- end }}

{{/*
Compose fromRepo URL
*/}}
{{- define "frontend-github-scaffolding.fromRepoUrl" -}}
{{- printf "%s/%s/%s" .Values.git.fromRepo.scmUrl .Values.git.fromRepo.org .Values.git.fromRepo.name }}
{{- end }}