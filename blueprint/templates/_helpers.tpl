{{/*
Expand the name of the chart.
*/}}
{{- define "github-scaffolding-with-composition-page.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "github-scaffolding-with-composition-page.fullname" -}}
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
{{- define "github-scaffolding-with-composition-page.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "github-scaffolding-with-composition-page.labels" -}}
helm.sh/chart: {{ include "github-scaffolding-with-composition-page.chart" . }}
{{ include "github-scaffolding-with-composition-page.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "github-scaffolding-with-composition-page.selectorLabels" -}}
app.kubernetes.io/name: {{ include "github-scaffolding-with-composition-page.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "github-scaffolding-with-composition-page.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "github-scaffolding-with-composition-page.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Compose toRepo URL
*/}}
{{- define "github-scaffolding-with-composition-page.toRepoUrl" -}}
{{- printf "%s/%s/%s" .Values.git.toRepo.scmUrl .Values.git.toRepo.org .Values.git.toRepo.name }}
{{- end }}

{{/*
Compose fromRepo URL
*/}}
{{- define "github-scaffolding-with-composition-page.fromRepoUrl" -}}
{{- printf "%s/%s/%s" .Values.git.fromRepo.scmUrl .Values.git.fromRepo.org .Values.git.fromRepo.name }}
{{- end }}