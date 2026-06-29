{{- define  "node-lrps.larp" }}
---
apiVersion: cilium.io/v2
kind: CiliumLocalRedirectPolicy
metadata:
  name: {{ .Release.Name }}-{{ .kind }}-{{ .node.address | replace "." "-" | replace ":" "-" | lower }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- toYaml .Values.labels | nindent 4 }}
spec:
  redirectFrontend:
    addressMatcher:
      ip: {{ .node.address | quote }}
      toPorts:
        {{- toYaml .toPorts | nindent 8 }}
  redirectBackend:
    localEndpointSelector:
      {{- toYaml .Values.localEndpointSelector | nindent 6 }}
    toPorts:
      {{- toYaml .toPorts | nindent 6 }}
{{- end }}
