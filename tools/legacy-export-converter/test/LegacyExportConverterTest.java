import java.util.List;

/**
 * Minimal, dependency-free test runner (no JUnit/Maven/Gradle -- this is a
 * two-file CLI utility, a build tool would be more machinery than the tool
 * itself). Run with test/run.sh. Exits non-zero if any assertion fails.
 */
public final class LegacyExportConverterTest {

    private static int failures = 0;

    public static void main(String[] args) throws Exception {
        testConvertLine_mapsFieldsInCanonicalOrder();
        testConvertLine_normalizesDateFormat();
        testConvertLine_lowercasesStatus();
        testConvertLine_quotesFieldsContainingCommas();
        testConvertLine_rejectsWrongFieldCount();
        testConvertFile_skipsHeaderAndBlankLines();

        if (failures > 0) {
            System.err.println(failures + " assertion(s) failed");
            System.exit(1);
        }
        System.out.println("All assertions passed");
    }

    static void testConvertLine_mapsFieldsInCanonicalOrder() {
        String legacy = "E-4471;Ada;Lovelace;ada@example.com;ENGINEERING;E-1000;03/14/2019;72000.00;Active";
        String canonical = LegacyExportConverter.convertLine(legacy, 2);
        assertEquals(
            "E-4471,Ada,Lovelace,ada@example.com,ENGINEERING,E-1000,2019-03-14,72000.00,active",
            canonical, "field mapping");
    }

    static void testConvertLine_normalizesDateFormat() {
        assertEquals("2019-03-14", LegacyExportConverter.normalizeDate("03/14/2019"), "date normalization");
        assertEquals("2019-03-04", LegacyExportConverter.normalizeDate("3/4/2019"), "single-digit date normalization");
    }

    static void testConvertLine_lowercasesStatus() {
        String legacy = "E-1;A;B;;ENGINEERING;;01/01/2020;50000;TERMINATED";
        String canonical = LegacyExportConverter.convertLine(legacy, 2);
        assertTrue(canonical.endsWith(",terminated"), "status should be lowercased, got: " + canonical);
    }

    static void testConvertLine_quotesFieldsContainingCommas() {
        String legacy = "E-1;A;B;;\"Sales, EMEA\";;01/01/2020;50000;active";
        String canonical = LegacyExportConverter.convertLine(legacy, 2);
        assertTrue(canonical.contains("\"\"Sales, EMEA\"\""), "comma-containing field should be quoted, got: " + canonical);
    }

    static void testConvertLine_rejectsWrongFieldCount() {
        try {
            LegacyExportConverter.convertLine("E-1;A;B", 5);
            fail("expected IllegalArgumentException for wrong field count");
        } catch (IllegalArgumentException expected) {
            assertTrue(expected.getMessage().contains("line 5"), "error message should reference the line number");
        }
    }

    static void testConvertFile_skipsHeaderAndBlankLines() throws Exception {
        java.io.File tmp = java.io.File.createTempFile("legacy-export", ".txt");
        tmp.deleteOnExit();
        try (java.io.PrintWriter w = new java.io.PrintWriter(new java.io.FileWriter(tmp))) {
            w.println("EmployeeID;GivenName;FamilyName;Email;Dept;Manager;HireDate;Salary;Status");
            w.println("E-1;A;One;a@example.com;ENGINEERING;;01/01/2020;50000;Active");
            w.println("");
            w.println("E-2;B;Two;b@example.com;SALES;E-1;02/02/2021;60000;Active");
        }

        List<String> rows = LegacyExportConverter.convertFile(tmp.getAbsolutePath());
        assertEquals(2, rows.size(), "row count (header and blank line should be skipped)");
    }

    private static void assertEquals(Object expected, Object actual, String label) {
        if (!expected.equals(actual)) {
            failures++;
            System.err.println("FAIL [" + label + "]: expected <" + expected + "> but got <" + actual + ">");
        }
    }

    private static void assertTrue(boolean condition, String message) {
        if (!condition) {
            failures++;
            System.err.println("FAIL: " + message);
        }
    }

    private static void fail(String message) {
        failures++;
        System.err.println("FAIL: " + message);
    }
}
