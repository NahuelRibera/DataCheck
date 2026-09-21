import java.io.BufferedReader;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;

/**
 * Converts a legacy on-prem HR export (semicolon-delimited, its own column
 * order and header names) into DataCheck's canonical employee CSV format.
 *
 * This is a standalone utility with one responsibility: format conversion.
 * It does no validation beyond "does this line have the right number of
 * fields" -- the actual data-quality analysis is scripts/profile_import.py's
 * job, run after this converter, not this tool's.
 *
 * Legacy format (semicolon-delimited, header row required):
 *   EmployeeID;GivenName;FamilyName;Email;Dept;Manager;HireDate;Salary;Status
 *
 * Canonical output (matches data/demo/*.csv):
 *   external_id,first_name,last_name,email,department_external_id,
 *   manager_external_id,start_date,gross_salary,status
 *
 * Usage:
 *   java LegacyExportConverter <input.txt> <output.csv>
 */
public final class LegacyExportConverter {

    static final String[] CANONICAL_HEADER = {
        "external_id", "first_name", "last_name", "email",
        "department_external_id", "manager_external_id",
        "start_date", "gross_salary", "status",
    };

    private static final int EXPECTED_FIELD_COUNT = 9;

    private LegacyExportConverter() {
    }

    public static void main(String[] args) throws IOException {
        if (args.length != 2) {
            System.err.println("Usage: java LegacyExportConverter <input.txt> <output.csv>");
            System.exit(2);
        }

        List<String> canonicalRows = convertFile(args[0]);
        writeCsv(args[1], canonicalRows);
        System.out.println("Converted " + canonicalRows.size() + " row(s) -> " + args[1]);
    }

    /** Reads a legacy semicolon-delimited file and returns canonical CSV data rows (no header). */
    static List<String> convertFile(String inputPath) throws IOException {
        List<String> canonicalRows = new ArrayList<>();
        try (BufferedReader reader = new BufferedReader(new FileReader(inputPath))) {
            String line = reader.readLine(); // header, discarded
            if (line == null) {
                return canonicalRows;
            }
            int lineNumber = 1;
            while ((line = reader.readLine()) != null) {
                lineNumber++;
                if (line.trim().isEmpty()) {
                    continue;
                }
                canonicalRows.add(convertLine(line, lineNumber));
            }
        }
        return canonicalRows;
    }

    /** Converts one legacy data line into one canonical CSV line. Package-visible for tests. */
    static String convertLine(String legacyLine, int lineNumber) {
        String[] fields = legacyLine.split(";", -1);
        if (fields.length != EXPECTED_FIELD_COUNT) {
            throw new IllegalArgumentException(
                "line " + lineNumber + ": expected " + EXPECTED_FIELD_COUNT
                    + " semicolon-delimited fields, got " + fields.length);
        }

        String employeeId = fields[0].trim();
        String givenName = fields[1].trim();
        String familyName = fields[2].trim();
        String email = fields[3].trim();
        String dept = fields[4].trim();
        String manager = fields[5].trim();
        String hireDate = normalizeDate(fields[6].trim());
        String salary = fields[7].trim();
        String status = fields[8].trim().toLowerCase();

        return String.join(",",
            csvField(employeeId), csvField(givenName), csvField(familyName), csvField(email),
            csvField(dept), csvField(manager), csvField(hireDate), csvField(salary), csvField(status));
    }

    /** Legacy exports use MM/DD/YYYY; canonical format is ISO 8601 (YYYY-MM-DD). */
    static String normalizeDate(String legacyDate) {
        if (legacyDate.isEmpty()) {
            return "";
        }
        String[] parts = legacyDate.split("/");
        if (parts.length != 3) {
            return legacyDate; // leave as-is; the Python profiler will flag it as invalid
        }
        String month = parts[0];
        String day = parts[1];
        String year = parts[2];
        return year + "-" + pad(month) + "-" + pad(day);
    }

    private static String pad(String twoDigitsOrOne) {
        return twoDigitsOrOne.length() == 1 ? "0" + twoDigitsOrOne : twoDigitsOrOne;
    }

    private static String csvField(String value) {
        if (value.contains(",") || value.contains("\"")) {
            return "\"" + value.replace("\"", "\"\"") + "\"";
        }
        return value;
    }

    // Force LF regardless of platform (println() would use the platform
    // line separator, i.e. CRLF on Windows) so output is byte-identical
    // across machines and matches the LF convention used everywhere else
    // in this repository.
    private static void writeCsv(String outputPath, List<String> dataRows) throws IOException {
        try (PrintWriter writer = new PrintWriter(new FileWriter(outputPath))) {
            writer.print(String.join(",", CANONICAL_HEADER));
            writer.print("\n");
            for (String row : dataRows) {
                writer.print(row);
                writer.print("\n");
            }
        }
    }
}
