class Api::V1::ServerSdkController < Api::V1::ProjectsBaseController
  include CustomRedirectsHandler
  include SdkLinkBuilder
  include Api::V1::Concerns::AnalyticsRetentionGate

  before_action :authenticate_request, except: []

  API_KEY_USED_TTL = 24.hours

  # With a `path`, creates the link on that path or updates the one already
  # there, so a server can keep one link per entity without a dashboard login.
  def generate_link
    link = build_and_save_sdk_link(platform_name: "API", fixed_path: fixed_path_param)

    render json: {link: link.access_path}, status: :ok
  end

  # Raw events of the project, oldest first, for a warehouse to pull
  # incrementally: start_date (ISO 8601) is required, `cursor` pages.
  def events
    start_time = parse_iso_time(params.require(:start_date))
    end_time = params[:end_date].present? ? parse_iso_time(params[:end_date]) : Time.current
    return render(json: { error: "start_date and end_date must be ISO 8601" }, status: :bad_request) unless start_time && end_time

    result = ::Analytics::EventsQueryService.list(
      @project.id,
      start_date: start_time,
      end_date: end_time,
      cursor: params[:cursor],
      limit: params[:limit].presence || ::Analytics::EventsQueryService::MAX_LIMIT,
      sort_by: "created_at",
      sort_order: "asc"
    )
    render json: { data: result[:data], next_cursor: result[:next_cursor] }, status: :ok
  end

  def link_details
    domain = @project.domain_for_project

    link = Link.includes(:custom_redirects, :domain).find_by(path: path_param, domain_id: domain.id)
    unless link
      render json: {error: "Link not found"}, status: :not_found
      return
    end


    render json: {link: LinkSerializer.serialize(link)}, status: :ok
  end

  def metrics_for_link
    domain = @project.domain_for_project
    link = Link.includes(:custom_redirects, :domain).find_by(path: path_param, domain_id: domain.id)
    unless link
      render json: {error: "Link not found"}, status: :not_found
      return
    end

    metrics = LinkStatisticsQuery.new(params: { link_id: link.id, sort_by: 'views', start_date: retention_floor(Time.at(0).to_date), active: link.active },
project: @project).call[:links][0]
    render json: {metrics: metrics}
  end

  def metrics_for_project
    metrics = LinkStatisticsQuery.new(params: { all: true, sort_by: 'views', start_date: retention_floor(Time.at(0).to_date), active: "true" },
project: @project).call[:links]
    render json: metrics
  end

  private

  def authenticate_request
    @project_key = request.headers['PROJECT-KEY'] || request.headers['project-key']
    @environment = request.headers['ENVIRONMENT'] || request.headers['environment']

    # Check if project key is missing
    if @project_key.blank?
      render json: { error: "Missing PROJECT-KEY in headers" }, status: :bad_request
      return false
    end

    instance = Instance.find_by(api_key: @project_key)

    # Validate environment
    unless %w[production test].include?(@environment)
      audit_api_key_failure(instance)
      render json: { error: "Invalid ENVIRONMENT value. Allowed: 'production', 'test'" }, status: :bad_request
      return false
    end

    @project = instance&.public_send(@environment == "test" ? :test : :production)

    unless @project
      audit_api_key_failure(instance)
      render json: { error: "Invalid credentials" }, status: :forbidden
      return false
    end

    Current.actor = AuditActor.api_key(instance)
    audit_api_key_use(instance)
    true
  end

  def audit_api_key_failure(instance)
    return unless instance

    audit_api_key_once_per_day(instance, "audit:api_key_failed", "api_key.auth_failed", "failure")
  end

  def audit_api_key_use(instance)
    audit_api_key_once_per_day(instance, "audit:api_key_used", "api_key.used", "success")
  end

  # First sighting of (key, ip) per day (ADR 0002). SET NX claims the slot atomically; a failed write releases it.
  def audit_api_key_once_per_day(instance, prefix, action, outcome)
    return unless instance.audit_log_enabled?

    key = "#{prefix}:#{instance.id}:#{request.remote_ip}"
    claimed = begin
      REDIS.with { |c| c.set(key, "1", nx: true, ex: API_KEY_USED_TTL.to_i) }
    rescue Redis::BaseError
      true
    end
    return unless claimed

    begin
      Audit.record(instance_id: instance.id, action: action, outcome: outcome, actor: AuditActor.api_key(instance),
                        target: Audit.target_for(instance))
    rescue StandardError
      begin
        REDIS.with { |c| c.del(key) }
      rescue Redis::BaseError
        nil
      end
      raise
    end
  end

  def parse_iso_time(value)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  # Params

  def title_param
    params.permit(:title)[:title]
  end

  def name_param
    params.permit(:name)[:name]
  end

  FIXED_PATH_FORMAT = /\A[A-Za-z0-9._-]{1,100}\z/

  def fixed_path_param
    path = params.permit(:path)[:path].presence
    return nil unless path
    raise ActionController::BadRequest, "path must be 1-100 chars of letters, digits, '.', '_' or '-'" unless FIXED_PATH_FORMAT.match?(path)

    path
  end

  def subtitle_param
    params.permit(:subtitle)[:subtitle]
  end

  def data_param
    params.permit(:data)[:data]
  end

  def tags_param
    params.permit(:tags)[:tags]
  end

  def id_param
    params.require(:id)
  end

  def path_param
    params.require(:path)
  end

  def show_preview_param
    params.permit(:show_preview)[:show_preview]
  end

  def show_preview_ios_param
    params.permit(:show_preview_ios)[:show_preview_ios]
  end

  def show_preview_android_param
    params.permit(:show_preview_android)[:show_preview_android]
  end

  def copy_to_clipboard_ios_param
    params.permit(:copy_to_clipboard_ios)[:copy_to_clipboard_ios]
  end

  def copy_to_clipboard_android_param
    params.permit(:copy_to_clipboard_android)[:copy_to_clipboard_android]
  end

  def tracking_campaign_param
    params.permit(:tracking_campaign)[:tracking_campaign]
  end

  def tracking_medium_param
    params.permit(:tracking_medium)[:tracking_medium]
  end

  def tracking_source_param
    params.permit(:tracking_source)[:tracking_source]
  end

end