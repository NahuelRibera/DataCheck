import { Controller } from "@hotwired/stimulus";

// Switches between labeled panels (Overview / Issues / Dry Run / Verification / Audit Trail)
// on the import run detail page. The active tab persists across reloads via the URL hash.
export default class TabsController extends Controller<HTMLElement> {
  static targets = ["tab", "panel"];

  declare readonly tabTargets: HTMLElement[];
  declare readonly panelTargets: HTMLElement[];

  connect(): void {
    const initial = window.location.hash.replace("#", "") || this.tabTargets[0]?.dataset.tabName;
    if (initial) this.activate(initial);
  }

  select(event: Event): void {
    const target = event.currentTarget as HTMLElement;
    const name = target.dataset.tabName;
    if (!name) return;
    history.replaceState(null, "", `#${name}`);
    this.activate(name);
  }

  private activate(name: string): void {
    this.tabTargets.forEach((tab) => {
      const isActive = tab.dataset.tabName === name;
      tab.classList.toggle("tab--active", isActive);
      tab.setAttribute("aria-selected", String(isActive));
    });
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.tabName !== name;
    });
  }
}
