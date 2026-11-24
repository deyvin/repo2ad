import { Controller } from "@hotwired/stimulus"

// Abre e fecha um <dialog> nativo (Gerar de novo na tela de resultado).
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}
