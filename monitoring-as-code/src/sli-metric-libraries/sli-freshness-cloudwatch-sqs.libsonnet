// Library to generate Grafana and Prometheus config for Cloudwatch SQS latency

// MaC imports
local sliMetricLibraryFunctions = import '../util/sli-metric-library-functions.libsonnet';

// Grafana imports
local grafana = import 'grafonnet/grafana.libsonnet';
local prometheus = grafana.prometheus;
local graphPanel = grafana.graphPanel;
local row = grafana.row;
local template = grafana.template;

// Creates Grafana dashboard graph panel for an SLI type
// @param sliSpec The spec for the SLI having its dashboard created
// @returns Grafana graph panel object
local createGraphPanel(sliSpec) =
  local metricConfig = sliMetricLibraryFunctions.getMetricConfig(sliSpec);
  local dashboardSelectors = sliMetricLibraryFunctions.createDashboardSelectors(metricConfig, sliSpec);
  local targetMetrics = sliMetricLibraryFunctions.getTargetMetrics(metricConfig, sliSpec);

  graphPanel.new(
    title = '%s' % sliSpec.sliDescription,
    description = |||
      * Sample interval is %(evalInterval)s
      * Resource selectors are %(selectors)s
      * Only queues where type is not deadletter
    ||| % {
      evalInterval: sliSpec.evalInterval,
      selectors: std.strReplace(std.join(', ', sliMetricLibraryFunctions.getSelectors(metricConfig, sliSpec)), '~', '\\~'),
    },
    datasource = 'prometheus',
    min = 0,
    fill = 0,
  ).addTarget(
    prometheus.target(
      'sum(avg_over_time(%(messagesDeletedMetric)s{%(selectors)s, %(queueSelector)s}
        [%(evalInterval)s]) or vector(0))' % {
          messagesDeletedMetric: targetMetrics.messagesDeleted,
          selectors: std.join(',', dashboardSelectors),
          queueSelector: '%s!~"%s"' % [metricConfig.customSelectorLabels.deadletterQueueName, metricConfig.customSelectors.deadletterQueueName],
          evalInterval: sliSpec.evalInterval,
        },
      legendFormat='avg number of msgs delivered',
    )
  ).addTarget(
    prometheus.target(
      'sum(avg_over_time(sqs_high_latency_in_queue_avg{%(dashboardSliLabelSelectors)s}[%(evalInterval)s])
        or vector(0))/ sum(count_over_time(%(oldestMessageMetric)s{%(selectors)s, %(queueSelector)s}
        [%(evalInterval)s]) or vector(0))' % {
          oldestMessageMetric: targetMetrics.oldestMessage,
          selectors: std.join(',', dashboardSelectors),
          queueSelector: '%s!~"%s"' % [metricConfig.customSelectorLabels.deadletterQueueName, metricConfig.customSelectors.deadletterQueueName],
          dashboardSliLabelSelectors: sliSpec.dashboardSliLabelSelectors,
          evalInterval: sliSpec.evalInterval,
        },
      legendFormat='avg period where msg in standard queue > %s seconds' % sliSpec.metricTarget,
    )
  ).addTarget(
    prometheus.target(
      'sum(avg_over_time(%(oldestMessageMetric)s{%(selectors)s, %(queueSelector)s}[%(evalInterval)s]) or vector(0))' % {
        oldestMessageMetric: targetMetrics.oldestMessage,
        selectors: std.join(',', dashboardSelectors),
        queueSelector: '%s!~"%s"' % [metricConfig.customSelectorLabels.deadletterQueueName, metricConfig.customSelectors.deadletterQueueName],
        evalInterval: sliSpec.evalInterval,
      },
      legendFormat='avg age of oldest msg in standard queue (secs)',
    )
  ).addSeriesOverride(
    {
      alias: '/avg age of oldest msg in standard queue/',
      yaxis: 2,
      color: 'orange',
    },
  ).addSeriesOverride(
    {
      alias: '/avg period where msg in standard queue > %s seconds/' % sliSpec.metricTarget,
      color: 'red',
    },
  ).addSeriesOverride(
    {
      alias: '/avg number of msgs delivered/',
      color: 'green',
    },
  );

// Creates custom recording rules for an SLI type
// @param sliSpec The spec for the SLI having its recording rules created
// @param sliMetadata Metadata about the type and category of the SLI
// @param config The config for the service defined in the mixin file
// @returns JSON defining the recording rules
local createCustomRecordingRules(sliSpec, sliMetadata, config) =
  local metricConfig = sliMetricLibraryFunctions.getMetricConfig(sliSpec);
  local ruleSelectors = sliMetricLibraryFunctions.createRuleSelectors(metricConfig, sliSpec, config);
  local targetMetrics = sliMetricLibraryFunctions.getTargetMetrics(metricConfig, sliSpec);

  [
    {
      record: 'sli_value',
      expr: |||
        (sum(avg_over_time(sqs_high_latency_in_queue_avg{%(ruleSliLabelSelectors)s}[%(evalInterval)s])) or vector(0))
        /
        (sum(count_over_time(%(oldestMessageMetric)s{%(selectors)s, %(queueSelector)s}[%(evalInterval)s])) or vector(0))
      ||| % {
        oldestMessageMetric: targetMetrics.oldestMessage,
        selectors: std.join(',', ruleSelectors),
        queueSelector: '%s!~"%s"' % [metricConfig.customSelectorLabels.deadletterQueueName, metricConfig.customSelectors.deadletterQueueName],
        ruleSliLabelSelectors: sliSpec.ruleSliLabelSelectors,
        evalInterval: sliSpec.evalInterval,
      },
      labels: sliSpec.sliLabels + sliMetadata,
    },
    {
      // unsure how to add to this expression
      record: 'sqs_high_latency_in_queue_avg',
      expr: |||
        (%(oldestMessageMetric)s{%(selectors)s, %(queueSelector)s} > bool %(metricTarget)s) or vector(0)
      ||| % {
        oldestMessageMetric: targetMetrics.oldestMessage,
        selectors: std.join(',', ruleSelectors),
        queueSelector: '%s!~"%s"' % [metricConfig.customSelectorLabels.deadletterQueueName, metricConfig.customSelectors.deadletterQueueName],
        metricTarget: sliSpec.metricTarget,
      },
      labels: sliSpec.sliLabels,
    },
  ];

// File exports
{
  createGraphPanel(sliSpec): createGraphPanel(sliSpec),
  createCustomRecordingRules(sliSpec, sliMetadata, config): createCustomRecordingRules(sliSpec, sliMetadata, config),
}
