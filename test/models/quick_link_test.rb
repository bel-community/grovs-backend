require "test_helper"

class QuickLinkTest < ActiveSupport::TestCase
  fixtures :quick_links, :domains, :projects, :instances

  # === full_path ===

  test "full_path constructs subdomain.domain/path" do
    ql = quick_links(:basic_quick_link)
    domain = ql.domain
    # QuickLink.full_path uses domain.subdomain + "." + domain.domain + "/" + path
    expected = "#{domain.subdomain}.#{domain.domain}/#{ql.path}"
    assert_equal expected, ql.full_path(domain)
  end

  test "full_path with blank subdomain still uses dot separator" do
    ql = quick_links(:basic_quick_link)
    domain = ql.domain
    domain.subdomain = "custom"
    result = ql.full_path(domain)
    assert_equal "custom.#{domain.domain}/#{ql.path}", result
  end

  # === access_path ===

  test "access_path prepends https" do
    ql = quick_links(:basic_quick_link)
    result = ql.access_path
    assert result.start_with?("https://")
    assert result.include?(ql.path)
  end

  test "every destination rejects a javascript: scheme, including host-bearing forms" do
    QuickLink::DESTINATIONS.each do |field|
      ql = quick_links(:basic_quick_link)
      ql[field] = "javascript:alert(1)"
      assert_not ql.valid?, "#{field} must reject javascript:"
      ql[field] = "javascript://example.com/%0aalert(1)"
      assert_not ql.valid?, "#{field} must reject javascript:// with a host"
      ql[field] = "https://example.com/?a=1&b=2"
      assert ql.valid?, "#{field} must accept https: #{ql.errors.full_messages}"
    end
  end

  test "a bare host is stored with https:// so it does not navigate relatively" do
    ql = quick_links(:basic_quick_link)
    ql.ios_phone = " www.example.com "
    assert ql.valid?, ql.errors.full_messages.inspect
    assert_equal "https://www.example.com", ql.ios_phone
  end

  test "custom app schemes are accepted, blocked schemes are refused in any casing or with leading whitespace" do
    ql = quick_links(:basic_quick_link)
    ql.ios_phone = "myapp://open/test?x=1"
    assert ql.valid?, ql.errors.full_messages.inspect
    ["  JavaScript:alert(1)", "data:text/html,<script>alert(1)</script>", "vbscript:msgbox"].each do |bad|
      ql.desktop = bad
      assert_not ql.valid?, "#{bad.inspect} must be rejected"
    end
  end

  test "destinations returns the eight fields in JS argument order with blanks as nil" do
    ql = quick_links(:basic_quick_link)
    ql.desktop = ""
    assert_equal QuickLink::DESTINATIONS.length, ql.destinations.length
    assert_nil ql.destinations[QuickLink::DESTINATIONS.index(:desktop)]
  end

  test "ios_phone with valid URL passes validation" do
    ql = quick_links(:basic_quick_link)
    ql.ios_phone = "https://apps.apple.com/app/id123"
    ql.validate
    assert_not ql.errors[:ios_phone].any?
  end

  test "ios_phone with invalid URL adds error" do
    ql = quick_links(:basic_quick_link)
    ql.ios_phone = "not a url"
    ql.validate
    assert ql.errors[:ios_phone].any?
  end

  test "blank ios_phone skips validation" do
    ql = quick_links(:no_url_quick_link)
    ql.ios_phone = ""
    ql.validate
    assert_not ql.errors[:ios_phone].any?
  end

  test "android_phone with valid URL passes validation" do
    ql = quick_links(:basic_quick_link)
    ql.android_phone = "https://play.google.com/store/apps/details?id=com.test"
    ql.validate
    assert_not ql.errors[:android_phone].any?
  end

  test "android_phone with invalid URL adds error" do
    ql = quick_links(:basic_quick_link)
    ql.android_phone = "not a url"
    ql.validate
    assert ql.errors[:android_phone].any?
  end

  test "blank android_phone skips validation" do
    ql = quick_links(:no_url_quick_link)
    ql.android_phone = ""
    ql.validate
    assert_not ql.errors[:android_phone].any?
  end

  test "optional URL fields with valid URLs pass" do
    ql = quick_links(:basic_quick_link)
    ql.ios_tablet = "https://example.com"
    ql.android_tablet = "https://example.com"
    ql.desktop_mac = "https://example.com"
    ql.desktop_windows = "https://example.com"
    ql.desktop_linux = "https://example.com"
    ql.validate
    %i[ios_tablet android_tablet desktop_mac desktop_windows desktop_linux].each do |field|
      assert_not ql.errors[field].any?, "Expected no errors for #{field}"
    end
  end

  test "optional URL fields with invalid URLs add errors" do
    ql = quick_links(:basic_quick_link)
    ql.ios_tablet = "notaurl"
    ql.validate
    assert ql.errors[:ios_tablet].any?
  end

  # === serialization ===

  test "serializer excludes internal fields and includes access_path" do
    ql = quick_links(:basic_quick_link)
    AssetService.stub(:permanent_url, nil) do
      json = QuickLinkSerializer.serialize(ql)
      assert_nil json["updated_at"]
      assert_nil json["created_at"]
      assert_nil json["id"]
      assert_nil json["domain_id"]
      assert_nil json["image_url"]
      assert json.key?("access_path")
      assert json.key?("image")
    end
  end
end
