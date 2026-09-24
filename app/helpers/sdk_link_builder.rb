module SdkLinkBuilder

  private

  # fixed_path (server SDK only): upsert on that path. Such links belong to a
  # server-side entity (a creator, a campaign), so they stay visible in the dashboard.
  def build_and_save_sdk_link(platform_name:, visitor: nil, image_url: nil, image: nil, fixed_path: nil)
    domain = @project.domain_for_project
    redirect_config = @project.redirect_config

    link = fixed_path && Link.find_by(domain: domain, path: fixed_path, active: true)
    link ||= Link.new(generated_from_platform: platform_name)
    path = fixed_path || LinksService.generate_valid_path(domain)

    link.title = title_param
    link.subtitle = subtitle_param
    link.name = name_param if fixed_path && name_param
    link.path = path
    link.domain = domain
    link.redirect_config = redirect_config
    link.sdk_generated = fixed_path.nil?
    link.image_url = image_url
    link.visitor = visitor

    # Tracking
    link.tracking_campaign = tracking_campaign_param
    link.tracking_source = tracking_source_param
    link.tracking_medium = tracking_medium_param

    if data_param
      link.data = JSON.parse(data_param)
    end

    if image
      link.image.attach(image)
    end

    if tags_param
      link.tags = JSON.parse(tags_param)
    end

    unless show_preview_param.nil?
      link.show_preview_ios = show_preview_param
      link.show_preview_android = show_preview_param
    end

    unless show_preview_ios_param.nil?
      link.show_preview_ios = show_preview_ios_param
    end

    unless show_preview_android_param.nil?
      link.show_preview_android = show_preview_android_param
    end

    unless copy_to_clipboard_ios_param.nil?
      link.copy_to_clipboard_ios = copy_to_clipboard_ios_param
    end

    unless copy_to_clipboard_android_param.nil?
      link.copy_to_clipboard_android = copy_to_clipboard_android_param
    end

    begin
      attempts ||= 0
      link.save!
    rescue ActiveRecord::RecordInvalid => e
      # No unique index on links: a lost path race surfaces as path_must_be_unique, not RecordNotUnique.
      raise if e.record.errors[:path].empty?
      # A fixed path lost the race to another request creating the same link: that link is the answer.
      if fixed_path
        existing = Link.find_by(domain: domain, path: fixed_path, active: true)
        return existing if existing
      end
      raise LinksService::PathGenerationError, "path race unresolved for domain #{domain.id}" if (attempts += 1) > 3

      link.path = LinksService.generate_valid_path(domain)
      retry
    end

    # Update custom redirects
    update_custom_redirects_for_link(link)

    link
  end
end
