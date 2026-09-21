require "csv"

module CsvHelpers
  HEADERS = %w[
    external_id first_name last_name email department_external_id
    manager_external_id start_date gross_salary status
  ].freeze

  def write_source_csv(import_run, rows)
    csv_string = CSV.generate(headers: true) do |csv|
      csv << HEADERS
      rows.each { |row| csv << HEADERS.map { |header| row[header.to_sym] } }
    end
    import_run.save_source_csv!(StringIO.new(csv_string))
  end

  def default_employee_row(overrides = {})
    {
      external_id: "EMP-001",
      first_name: "Ada",
      last_name: "Lovelace",
      email: "ada@example.com",
      department_external_id: nil,
      manager_external_id: nil,
      start_date: "2024-01-01",
      gross_salary: "50000.00",
      status: "active",
    }.merge(overrides)
  end
end
