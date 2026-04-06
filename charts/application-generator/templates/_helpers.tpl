{{- define "better-tpl" }}
    {{- $val := index . 0 }}
    {{- $ctx := index . 1 }}
    {{- if not (typeIs "string" $val) -}}
        {{- $val = toYaml $val -}}
    {{- end -}}
    {{- if contains "{{" $val }}
        {{- $val := tpl $val $ctx }}
        {{- include "better-tpl" (list $val $ctx ) }}
    {{- else }}
        {{- $val }}
    {{- end }}
{{- end }}

{{- define "resolve-upstream-stage" -}}
{{- /* Walk the promotedFrom chain, skipping disabled envs.
     Returns the first reachable env name, or "direct" if the chain is exhausted. */ -}}
{{- $envName := index . "envName" }}
{{- $Values  := index . "Values" }}
{{- $app     := index . "app" }}
{{- $env     := index $Values.envs $envName }}
{{- $skip    := false }}
{{- if eq $env.enabled false }}{{- $skip = true }}{{- end }}
{{- if $skip }}
  {{- if $env.promotedFrom }}
    {{- include "resolve-upstream-stage" (dict "envName" $env.promotedFrom "Values" $Values "app" $app) }}
  {{- else -}}direct{{- end }}
{{- else -}}{{ $envName }}{{- end }}
{{- end }}