# =============================================================================
# EKS-only overlay for the Splunk Astronomy Shop collector values.
# =============================================================================
# Helm file order:
#   1. splunk-otel-collector-values.yaml          (this repo: gateway, queues)
#   2. astronomy-shop/collector-values.yaml       (downloaded with the shop release)
#   3. this file                                  (wins on duplicate keys)
#
# The downloaded release owns shop receivers (SQL, flagd filters, loadgen).
# This file only restores the EKS gateway hop and the Fargate trace filter.
# =============================================================================

%{ if fargate_enabled ~}
# A previous Helm release can leave clusterReceiver.enabled=false. Set it explicitly.
clusterReceiver:
  enabled: true
%{ endif ~}

%{ if !fargate_enabled ~}
# Chart 0.157 renamed this processor to resourcedetection. The shop release
# pipelines still list resource_detection, and the agent exits before it can
# receive traces when that name is missing.
agent:
  config:
    processors:
      resource_detection:
        detectors: [env, eks, system]
        override: true
        timeout: 15s
        eks:
          node_from_env_var: K8S_NODE_NAME
      # Envoy's client span names the upstream cluster but does not set
      # peer.service. Splunk draws the service-map edge from that attribute,
      # so frontend-proxy otherwise never connects to frontend.
      transform/envoy_peer_service:
        error_mode: ignore
        trace_statements:
          - context: span
            statements:
              - set(attributes["peer.service"], attributes["upstream_cluster"]) where kind == SPAN_KIND_CLIENT and attributes["upstream_cluster"] != nil and attributes["peer.service"] == nil
%{ if gateway_enabled ~}
    # Release values export from the agent straight to Splunk. On EC2, agents
    # forward to the gateway Deployment instead. Helm replaces exporter lists,
    # so only those lists are set here; release processors and receivers stay.
    service:
      pipelines:
        # The shop release always lists filter/logs and resource/logs. Chart
        # 0.157 only creates those processors when the gateway is disabled,
        # because the gateway applies them. Leaving the names in the agent
        # pipeline makes the agent reject its whole config, including traces.
        logs:
          exporters:
            - otlp_grpc
          processors:
            - memory_limiter
            - k8s_attributes
            - batch
            - resourcedetection
            - resource
            - resource/add_environment
        metrics:
          exporters:
            - otlp_grpc
            - signalfx/host_metadata
        traces:
          exporters:
            - otlp_grpc
          processors:
            - memory_limiter
            - filter/drop_flagd
            - filter/drop_health_checks
            - transform/dc_not_error
            - transform/envoy_peer_service
            - k8s_attributes
            - batch
            - resource_detection
            - resource
            # Do not run the shop resource/add_environment here. The gateway
            # upserts deployment.environment to the workshop name on every span,
            # which is the same value RUM reads from the workshop secret.
%{ endif ~}
%{ endif ~}

%{ if fargate_enabled && gateway_enabled ~}
# Fargate has no agent DaemonSet. Flagd streaming spans must be dropped on the
# gateway or Splunk ingest returns HTTP 500. Do not add resourcedetection here;
# it would stamp every span with the gateway pod. Apps send k8s.pod.uid so
# k8s_attributes can associate by UID.
gateway:
  config:
    processors:
      filter/drop_flagd:
        traces:
          span:
          - attributes["rpc.method"] == "EventStream"
          - attributes["rpc.method"] == "ResolveAll"
          - attributes["rpc.method"] == "ResolveBoolean"
          - attributes["rpc.method"] == "ResolveFloat"
          - attributes["rpc.method"] == "ResolveInt"
          - attributes["http.url"] == "http://flagd:8016/ofrep/v1/evaluate/flags/loadGeneratorFloodHomepage"
          - attributes["url.full"] == "http://flagd:8013/flagd.evaluation.v1.Service/ResolveBoolean"
          - attributes["otel.scope.name"] == "flagd.evaluation.v1"
          - attributes["url.full"] == "http://flagd:8013/flagd.evaluation.v1.Service/EventStream"
      transform/trace_infra_correlation:
        error_mode: ignore
        trace_statements:
          - context: resource
            statements:
              - set(attributes["service.instance.id"], attributes["k8s.pod.uid"]) where attributes["k8s.pod.uid"] != nil and attributes["service.instance.id"] == nil
      transform/logs_service_map:
        error_mode: ignore
        log_statements:
          - context: log
            statements:
              - set(resource.attributes["service.name"], "payment") where resource.attributes["service.name"] == "paymentservice"
              - set(resource.attributes["service.name"], attributes["service.name"]) where resource.attributes["service.name"] == nil and attributes["service.name"] != nil
              - set(resource.attributes["deployment.environment"], attributes["deployment.environment"]) where resource.attributes["deployment.environment"] == nil and attributes["deployment.environment"] != nil
    service:
      pipelines:
        logs:
          exporters:
            - splunk_hec/o11y
            - splunk_hec/platform_logs
          processors: [memory_limiter, k8s_attributes, filter/logs, transform/logs_service_map, batch, resource/logs, resource/add_environment]
          receivers: [routing/logs]
        traces:
          exporters:
            - otlp_http
          processors: [memory_limiter, filter/drop_flagd, k8s_attributes, transform/trace_infra_correlation, batch, resource/add_cluster_name, resource/add_environment]
          receivers: [otlp, jaeger, zipkin]
%{ endif ~}
