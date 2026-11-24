import { Controller } from "@hotwired/stimulus"

// Seleção do cardápio: conta os criativos marcados e só deixa Gerar ligado com pelo menos um.
export default class extends Controller {
  static targets = ["checkbox", "count", "submit"]

  connect() {
    this.update()
  }

  update() {
    const selected = this.checkboxTargets.filter((box) => box.checked).length
    if (this.hasCountTarget) this.countTarget.textContent = `${selected} selecionado(s)`
    if (this.hasSubmitTarget) this.submitTarget.disabled = selected === 0
  }
}
