import { Controller } from "@hotwired/stimulus";

// Toggles the visibility of a details panel, used for expanding an issue row's
// full diagnostic message/metadata without navigating away.
export default class ExpandableController extends Controller<HTMLElement> {
  static targets = ["content", "toggleLabel"];

  declare readonly contentTarget: HTMLElement;
  declare readonly hasToggleLabelTarget: boolean;
  declare readonly toggleLabelTarget: HTMLElement;

  toggle(): void {
    const collapsed = this.contentTarget.hidden;
    this.contentTarget.hidden = !collapsed;
    if (this.hasToggleLabelTarget) {
      this.toggleLabelTarget.textContent = collapsed ? "Hide details" : "Show details";
    }
  }
}
