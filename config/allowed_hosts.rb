# Host header allow-list for production (see docs/configuration.md).
# Lives in config/ rather than lib/ because production.rb needs it before
# autoloading is available.
module AllowedHosts
  ENV_NAME = "DATA_CHECK_ALLOWED_HOSTS".freeze
  HEALTH_CHECK_PATH = "/up".freeze

  # Raised for an entry Rails would read as more than one exact host name.
  class InvalidEntry < ArgumentError; end

  # The health check is answered for any Host header.
  EXCLUDE_HEALTH_CHECK = ->(request) { request.path == HEALTH_CHECK_PATH }

  # Splits a comma-separated value into host names, dropping blanks and
  # surrounding whitespace. Returns [] for nil or an empty value.
  #
  # Rails treats a string with a leading dot (".example.com") as "this domain
  # and every subdomain", so such entries are refused rather than passed on:
  # each allowed host has to be listed explicitly.
  def self.parse(value)
    hosts = value.to_s.split(",").map(&:strip).reject(&:empty?)
    hosts.each do |host|
      next unless host.start_with?(".")

      raise InvalidEntry,
            "#{ENV_NAME}: entry #{host.inspect} starts with a dot, which would allow every subdomain; " \
            "list each host name explicitly"
    end
    hosts
  end
end
