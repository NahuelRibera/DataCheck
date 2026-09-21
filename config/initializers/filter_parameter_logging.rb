# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn,
  # DataCheck handles synthetic HR/payroll-like data. No current controller
  # action accepts these as top-level params (employee data only ever
  # arrives inside an uploaded CSV file, which Rails does not log the
  # contents of), but filtering them here is a deliberate, cheap backstop
  # against a future action logging them by accident.
  :email, :first_name, :last_name, :salary, :gross_salary, :gross_salary_cents
]
