# Host header allow-list for production (see docs/configuration.md).
# Lives in config/ rather than lib/ because production.rb needs it before
# autoloading is available.
module AllowedHosts
  ENV_NAME = "DATA_CHECK_ALLOWED_HOSTS".freeze
  HEALTH_CHECK_PATH = "/up".freeze

  # The health check is answered for any Host header.
  EXCLUDE_HEALTH_CHECK = ->(request) { request.path == HEALTH_CHECK_PATH }

  # Splits a comma-separated value into host names, dropping blanks and
  # surrounding whitespace. Returns [] for nil or an empty value.
  def self.parse(value)
    value.to_s.split(",").map(&:strip).reject(&:empty?)
  end
end
