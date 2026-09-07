namespace :purchase_events do
  desc "Enqueue unprocessed purchase events for processing"
  task process_unprocessed: :environment do
    scope = ProcessUnprocessedPurchaseEventsJob.stranded(min_age: 0, max_age: nil)

    total = scope.count
    puts "Enqueuing #{total} unprocessed purchase events"

    scope.find_each do |event|
      ProcessPurchaseEventJob.perform_async(event.id)
    end

    puts "Done — enqueued #{total} events"
  end
end
