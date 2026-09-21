module ApplicationHelper
  STATUS_BADGE_CLASSES = {
    "uploaded" => "gray",
    "profiling" => "blue",
    "blocked" => "red",
    "ready" => "blue",
    "dry_run_completed" => "blue",
    "importing" => "blue",
    "completed" => "green",
    "failed" => "red",
  }.freeze

  SEVERITY_BADGE_CLASSES = { "blocking" => "red", "warning" => "amber" }.freeze

  def status_badge(status)
    css = STATUS_BADGE_CLASSES.fetch(status, "gray")
    content_tag(:span, status.to_s.humanize, class: "badge badge--#{css}")
  end

  def severity_badge(severity)
    css = SEVERITY_BADGE_CLASSES.fetch(severity, "gray")
    content_tag(:span, severity.to_s.humanize, class: "badge badge--#{css}")
  end

  def check_badge(status)
    css = status == "pass" ? "green" : "red"
    content_tag(:span, status.upcase, class: "badge badge--#{css}")
  end

  def format_money_cents(cents)
    return "—" if cents.nil?

    number_to_currency(cents / 100.0)
  end
end
