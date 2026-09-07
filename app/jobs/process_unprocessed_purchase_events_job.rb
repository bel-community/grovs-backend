class ProcessUnprocessedPurchaseEventsJob
  include Sidekiq::Job
  sidekiq_options queue: :maintenance, retry: 0

  MIN_AGE = 5.minutes
  MAX_AGE = 30.days

  # Purchases whose ProcessPurchaseEventJob enqueue was lost after the row committed (Redis blip, replay short-circuit).
  # A row that already exhausted its retries is a poison row for a human, not for this loop.
  def self.stranded(min_age: MIN_AGE, max_age: MAX_AGE)
    PurchaseEvent.where(processed: false)
                 .where("webhook_validated = true OR store = false")
                 .where(created_at: (max_age&.ago)..min_age.ago)
                 .where.not(id: FailedPurchaseJob.where(job_class: "ProcessPurchaseEventJob", status: "pending")
                                                 .where.not(purchase_event_id: nil).select(:purchase_event_id))
  end

  def perform
    return unless Grovs.ee?

    self.class.stranded.find_each { |event| ProcessPurchaseEventJob.perform_async(event.id) }
  end
end
