# ActiveRecord logs INSERT/UPDATE statements with their values inlined into
# the SQL text (not as binds) in some code paths, and ActiveRecord's bind
# filtering (filter_parameters / filter_attributes) never applies to that
# text. For `employees` that would copy names, emails and salaries into the
# log, so those statements are logged with the values redacted.
module RedactSensitiveSqlLogging
  SENSITIVE_WRITE = /\A\s*(INSERT INTO|UPDATE)\s+"employees"/i

  def sql(event)
    statement = event.payload[:sql]
    if statement.is_a?(String) && (match = statement.match(SENSITIVE_WRITE))
      event.payload[:sql] = %(#{match[1].upcase} "employees" [values redacted])
    end
    super
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::LogSubscriber.prepend(RedactSensitiveSqlLogging)
end
