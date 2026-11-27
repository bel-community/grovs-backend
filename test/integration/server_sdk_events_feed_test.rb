require "test_helper"
require_relative "auth_test_helper"

class ServerSdkEventsFeedTest < ActionDispatch::IntegrationTest
  include AuthTestHelper

  fixtures :instances, :projects

  setup do
    @project = projects(:one)
    @headers = server_sdk_headers_for(@project)
  end

  test "events feed asks for each event's properties, oldest first" do
    captured = nil
    event = { "event_id" => "evt_1", "event_type" => "custom", "event_name" => "app_updated",
              "properties" => { "previous_version" => "12.13.0" } }
    fake = lambda do |*args, **kw|
      captured = [args, kw]
      { data: [event], next_cursor: nil, total_count: nil }
    end

    ::Analytics::EventsQueryService.stub(:list, fake) do
      get "#{SDK_PREFIX}/events", params: { start_date: "2026-11-01T00:00:00Z" }, headers: @headers
    end

    assert_response :ok
    assert_equal @project.id, captured[0][0]
    assert_equal true, captured[1][:include_properties]
    assert_equal "asc", captured[1][:sort_order]
    assert_equal({ "previous_version" => "12.13.0" }, JSON.parse(response.body)["data"].first["properties"])
  end
end
