"""Static reference data shared between the synthetic data generator and the
Rails demo seed task. Both sides hardcode the same company/department
external_ids so a freshly seeded database lines up with the generated CSVs
without needing an extra coupling file.
"""

COMPANY_EXTERNAL_ID = "ACME-HR"
COMPANY_NAME = "Acme Robotics Inc."

DEPARTMENTS = [
    ("DEPT-ENG", "Engineering"),
    ("DEPT-SAL", "Sales"),
    ("DEPT-MKT", "Marketing"),
    ("DEPT-FIN", "Finance"),
    ("DEPT-PPL", "People & HR"),
    ("DEPT-OPS", "Operations"),
    ("DEPT-SUP", "Customer Support"),
    ("DEPT-LEG", "Legal"),
]

DEPARTMENT_CODES = [code for code, _ in DEPARTMENTS]
