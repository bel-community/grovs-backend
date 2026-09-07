class AddAccountedUsdPriceCentsToPurchaseEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :purchase_events, :accounted_usd_price_cents, :bigint
    # Settled rows have their current price in the stats. A row updated in the last hour may have a correction
    # still queued against the old price; leaving it NULL lets that job trust its argument.
    execute <<~SQL
      UPDATE purchase_events SET accounted_usd_price_cents = COALESCE(usd_price_cents, 0)
      WHERE processed AND updated_at < NOW() - INTERVAL '1 hour'
    SQL
  end

  def down
    remove_column :purchase_events, :accounted_usd_price_cents
  end
end
