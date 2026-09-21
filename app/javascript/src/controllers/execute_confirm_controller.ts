import { Controller } from "@hotwired/stimulus";

// Requires the operator to type a literal confirmation phrase before the
// "Execute migration" form can be submitted. Migrations mutate production
// employee data, so this is a deliberate speed bump rather than a plain
// window.confirm() dialog.
export default class ExecuteConfirmController extends Controller<HTMLFormElement> {
  static targets = ["panel", "trigger", "input", "submit"];
  static values = { phrase: String };

  declare readonly panelTarget: HTMLElement;
  declare readonly triggerTarget: HTMLElement;
  declare readonly inputTarget: HTMLInputElement;
  declare readonly submitTarget: HTMLButtonElement;
  declare readonly phraseValue: string;

  connect(): void {
    this.submitTarget.disabled = true;
  }

  reveal(): void {
    this.triggerTarget.hidden = true;
    this.panelTarget.hidden = false;
    this.inputTarget.focus();
  }

  cancel(): void {
    this.panelTarget.hidden = true;
    this.triggerTarget.hidden = false;
    this.inputTarget.value = "";
    this.submitTarget.disabled = true;
  }

  validate(): void {
    this.submitTarget.disabled = this.inputTarget.value.trim() !== this.phraseValue;
  }
}
