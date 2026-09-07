# Replays CH batches parked in the DLQs (events + purchases) once ClickHouse is back.
# Nothing else drains them in production, so without this they grow forever. Idempotent:
# both `events` and `purchase_events` are ReplacingMergeTree (dedup by event_id /
# transaction_id), so replaying an already-delivered batch just collapses.
class DrainCanonicalDlqJob < ApplicationJob
  include SingleFlightJob

  queue_as :maintenance

  DRAIN_LIMIT = 100
  LOCK_TTL = 10.minutes
  # Fraction of the DLQ cap at which a sustained backlog risks silent drops (LTRIM).
  ALERT_FRACTION = 0.5

  def perform
    total = 0
    single_flight!(key: "drain_canonical_dlq", ttl: LOCK_TTL) do |deadline|
      canonical = ClickhouseWriteService.drain_canonical_dlq(limit: DRAIN_LIMIT, deadline: deadline)
      purchases = ClickhouseWriteService.drain_purchase_dlq(limit: DRAIN_LIMIT, deadline: deadline)
      total = canonical.to_i + purchases.to_i
      Rails.logger.info(message: "drain_clickhouse_dlqs", canonical: canonical, purchases: purchases) if total > 0
    end
    total
  rescue StandardError => e
    # Isolated: a drain failure must never crash the maintenance cron or raise.
    Rails.logger.error("DrainCanonicalDlqJob: drain failed: #{e.class} - #{e.message}")
  ensure
    report_depth
  end

  private

  # Sample the residual backlog so OTel/NewRelic can alert on it, and log loudly once it
  # nears the cap where the oldest parked batches would be silently dropped.
  def report_depth
    depth = ClickhouseWriteService.dlq_depth
    Grovs::Metrics.histogram("clickhouse.dlq.depth", depth)

    cap = ClickhouseWriteService::CANONICAL_DLQ_MAX
    Rails.logger.error(message: "clickhouse_dlq_backlog", depth: depth, cap: cap) if depth >= cap * ALERT_FRACTION
  end
end
