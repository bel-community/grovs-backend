class QuickLink < ApplicationRecord
  belongs_to :domain

  has_one_attached :image

  DESTINATIONS = %i[ios_phone ios_tablet android_phone android_tablet desktop desktop_mac desktop_windows desktop_linux].freeze
  # Every destination lands in window.location.href on the public page; these would run script there.
  BLOCKED_SCHEMES = %w[javascript data vbscript blob file about].freeze

  validate :path_must_be_unique, on: :create
  before_validation :prefix_bare_hosts
  validate :destinations_must_be_navigable

  def image_resource
    if image_url
      return image_url
    end
      
    AssetService.permanent_url(image)
  end

  def valid_path?
    link = Link.find_by(domain: domain, path: path)
    link.nil?
  end

  # Validations
  def path_must_be_unique
    unless valid_path?
      errors.add(:path, "There's an existing link for this domain and path")
    end
  end

  def full_path(domain)
    "#{domain.display_host}/#{path}"
  end

  def access_path
    "https://#{full_path(domain)}"
  end

  def destinations
    DESTINATIONS.map { |f| self[f].presence }
  end

  # "www.example.com" was accepted before; stored as-is it navigates relatively, so give it the scheme it implies.
  def prefix_bare_hosts
    DESTINATIONS.each do |field|
      value = self[field].to_s.strip
      next if value.blank? || scheme_of(value) || !value.include?(".") || value.include?(" ")

      self[field] = "https://#{value}"
    end
  end

  # Any scheme (https, myapp://) except the blocked ones; scheme-less values would navigate relatively.
  def destinations_must_be_navigable
    DESTINATIONS.each do |field|
      next if self[field].blank?

      scheme = scheme_of(self[field])
      errors.add(field, "must be a valid URL") if scheme.blank? || BLOCKED_SCHEMES.include?(scheme)
    end
  end

  def scheme_of(value)
    URI.parse(value.strip).scheme&.downcase
  rescue URI::InvalidURIError
    nil
  end
end
