import { Controller } from "@hotwired/stimulus";

// Client-side filtering of already-rendered issue rows by severity, issue type,
// and a free-text search over the row's visible text. Avoids a round trip for
// what is fundamentally a small, already-loaded dataset (an ImportRun's issues).
export default class IssueFilterController extends Controller<HTMLElement> {
  static targets = ["row", "severitySelect", "typeSelect", "search", "emptyState", "count"];

  declare readonly rowTargets: HTMLElement[];
  declare readonly severitySelectTarget: HTMLSelectElement;
  declare readonly typeSelectTarget: HTMLSelectElement;
  declare readonly searchTarget: HTMLInputElement;
  declare readonly emptyStateTarget: HTMLElement;
  declare readonly countTarget: HTMLElement;
  declare readonly hasEmptyStateTarget: boolean;
  declare readonly hasCountTarget: boolean;

  connect(): void {
    this.apply();
  }

  apply(): void {
    const severity = this.severitySelectTarget.value;
    const type = this.typeSelectTarget.value;
    const query = this.searchTarget.value.trim().toLowerCase();

    let visibleCount = 0;

    this.rowTargets.forEach((row) => {
      const matchesSeverity = !severity || row.dataset.severity === severity;
      const matchesType = !type || row.dataset.issueType === type;
      const matchesQuery = !query || (row.textContent || "").toLowerCase().includes(query);
      const visible = matchesSeverity && matchesType && matchesQuery;
      row.hidden = !visible;
      if (visible) visibleCount += 1;
    });

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.hidden = visibleCount !== 0;
    }
    if (this.hasCountTarget) {
      this.countTarget.textContent = String(visibleCount);
    }
  }
}
