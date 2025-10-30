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