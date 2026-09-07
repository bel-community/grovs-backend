require "test_helper"

class StripeWebhookOrderingTest < ActiveSupport::TestCase
  fixtures :instances, :stripe_payment_intents, :stripe_subscriptions, :stripe_webhook_messages

  setup do
    @instance = instances(:one)
    @payment_intent = stripe_payment_intents(:one)
    @active_sub = stripe_subscriptions(:active_sub)
  end

  def build_event(type:, object:)
    Stripe::Event.construct_from(id: "evt_test_#{SecureRandom.hex(4)}", type: type, data: { object: object })
  end

  test "checkout.session.completed creates a StripeSubscription with correct attributes" do
    StripeSubscription.where(instance_id: @instance.id).delete_all

    event_data = build_event(
      type: "checkout.session.completed",
      object: { subscription: "sub_new_123", customer: "cus_new_123", client_reference_id: @instance.id.to_s }
    )

    Stripe::Subscription.stub(:retrieve, ->(_) { raise Stripe::StripeError, "API error" }) do
      assert_difference "StripeSubscription.count", 1 do
        assert_raises(Stripe::StripeError) { StripeService.handle_webhook(event_data) }
      end
    end
    assert_not StripeWebhookMessage.find_by(stripe_event_id: event_data["id"]).processed, "left for Stripe to redeliver"

    sub = StripeSubscription.find_by(subscription_id: "sub_new_123")
    assert_not_nil sub
    assert_equal @instance.id, sub.instance_id
    assert_equal "cus_new_123", sub.customer_id
    assert_equal @payment_intent.product_type, sub.product_type
    assert_equal @payment_intent.id, sub.stripe_payment_intent_id
    assert_equal "pending", sub.status
    assert_equal false, sub.active
  end

  test "a redelivered checkout after a failed hydration reuses the pending row and activates it" do
    StripeSubscription.where(instance_id: @instance.id).delete_all
    event_data = build_event(
      type: "checkout.session.completed",
      object: { subscription: "sub_retry", customer: "cus_retry", client_reference_id: @instance.id.to_s }
    )
    Stripe::Subscription.stub(:retrieve, ->(_) { raise Stripe::StripeError, "API error" }) do
      assert_raises(Stripe::StripeError) { StripeService.handle_webhook(event_data) }
    end

    remote = Stripe::Subscription.construct_from(id: "sub_retry", status: "active", items: { data: [{ id: "si_retry" }] })
    Stripe::Subscription.stub(:retrieve, ->(_) { remote }) do
      assert_no_difference("StripeSubscription.count") { StripeService.handle_webhook(event_data) }
    end

    sub = StripeSubscription.find_by(subscription_id: "sub_retry")
    assert sub.active
    assert_equal "si_retry", sub.subscription_item_id
    assert StripeWebhookMessage.find_by(stripe_event_id: event_data["id"]).processed
  end

  test "checkout.session.completed hydrates status and item id from Stripe (subscription.created may already be gone)" do
    StripeSubscription.where(instance_id: @instance.id).delete_all
    @instance.update!(quota_exceeded: true)
    remote = Stripe::Subscription.construct_from(id: "sub_new_456", status: "active", items: { data: [{ id: "si_456" }] })
    event_data = build_event(
      type: "checkout.session.completed",
      object: { subscription: "sub_new_456", customer: "cus_new_456", client_reference_id: @instance.id.to_s }
    )

    Stripe::Subscription.stub(:retrieve, ->(_id) { remote }) do
      StripeService.handle_webhook(event_data)
    end

    sub = StripeSubscription.find_by(subscription_id: "sub_new_456")
    assert_equal "active", sub.status
    assert sub.active
    assert_equal "si_456", sub.subscription_item_id
    assert_not @instance.reload.quota_exceeded
  end

  test "the original ordering bug: created arrives first and is acknowledged, checkout still ends active" do
    StripeSubscription.where(instance_id: @instance.id).delete_all
    created = build_event(type: "customer.subscription.created",
                          object: { id: "sub_early", status: "active", items: { data: [{ id: "si_early" }] } })
    StripeService.handle_webhook(created)
    assert StripeWebhookMessage.find_by(stripe_event_id: created["id"]).processed, "no local row yet, acknowledged anyway"
    assert_nil StripeSubscription.find_by(subscription_id: "sub_early")

    checkout = build_event(type: "checkout.session.completed",
                           object: { subscription: "sub_early", customer: "cus_early", client_reference_id: @instance.id.to_s })
    remote = Stripe::Subscription.construct_from(id: "sub_early", status: "active", items: { data: [{ id: "si_early" }] })
    Stripe::Subscription.stub(:retrieve, ->(_) { remote }) { StripeService.handle_webhook(checkout) }

    sub = StripeSubscription.find_by(subscription_id: "sub_early")
    assert sub.active
    assert_equal "si_early", sub.subscription_item_id
  end

  test "a payment-mode checkout with no subscription id is ignored" do
    event_data = build_event(type: "checkout.session.completed",
                             object: { subscription: nil, customer: "cus_pay", client_reference_id: @instance.id.to_s })
    Stripe::Subscription.stub(:retrieve, ->(_) { flunk "must not call Stripe" }) do
      assert_no_difference("StripeSubscription.count") { StripeService.handle_webhook(event_data) }
    end
    assert StripeWebhookMessage.find_by(stripe_event_id: event_data["id"]).processed
  end

  test "a late incomplete subscription.created does not disable an already-active subscription" do
    @active_sub.update!(active: true, status: "active", subscription_item_id: nil)
    event_data = build_event(
      type: "customer.subscription.created",
      object: { id: @active_sub.subscription_id, status: "incomplete", items: { data: [{ id: "si_late" }] } }
    )

    StripeService.handle_webhook(event_data)

    @active_sub.reload
    assert @active_sub.active
    assert_equal "active", @active_sub.status
    assert_equal "si_late", @active_sub.subscription_item_id
  end

  test "customer.subscription.updated fills in a missing subscription_item_id" do
    @active_sub.update!(subscription_item_id: nil)
    event_data = build_event(
      type: "customer.subscription.updated",
      object: { id: @active_sub.subscription_id, customer: @active_sub.customer_id, status: "active",
                items: { data: [{ id: "si_filled" }] } }
    )

    StripeService.handle_webhook(event_data)

    assert_equal "si_filled", @active_sub.reload.subscription_item_id
  end
end
