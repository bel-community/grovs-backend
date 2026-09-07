require "test_helper"

class ProcessUnprocessedPurchaseEventsJobTest < ActiveSupport::TestCase
  fixtures :instances, :projects, :devices

  def purchase(created_at:, **attrs)
    PurchaseEvent.create!({ project: projects(:one), device: devices(:ios_device), event_type: "buy", price_cents: 100,
                            currency: "USD", transaction_id: "sweep-#{SecureRandom.hex(4)}", store: true,
                            webhook_validated: true, processed: false, created_at: created_at }.merge(attrs))
  end

  test "re-enqueues validated-but-unprocessed purchases older than the grace window" do
    PurchaseEvent.delete_all
    stranded = purchase(created_at: 10.minutes.ago)
    purchase(created_at: 1.minute.ago)
    purchase(created_at: 10.minutes.ago, processed: true)
    purchase(created_at: 10.minutes.ago, webhook_validated: false)
    purchase(created_at: 45.days.ago)
    poison = purchase(created_at: 10.minutes.ago)
    FailedPurchaseJob.create!(job_class: "ProcessPurchaseEventJob", arguments: [poison.id], error_class: "RuntimeError",
                              error_message: "bad currency", purchase_event_id: poison.id, project_id: poison.project_id,
                              failed_at: Time.current)
    validation_blip = purchase(created_at: 10.minutes.ago)
    FailedPurchaseJob.create!(job_class: "ValidatePurchaseEventJob", arguments: [validation_blip.id], error_class: "Timeout",
                              error_message: "apple down", purchase_event_id: validation_blip.id,
                              project_id: validation_blip.project_id, failed_at: Time.current)

    enqueued = []
    ProcessPurchaseEventJob.stub(:perform_async, ->(id) { enqueued << id }) do
      ProcessUnprocessedPurchaseEventsJob.new.perform
    end

    assert_equal [stranded.id, validation_blip.id].sort, enqueued.sort
  end
end
