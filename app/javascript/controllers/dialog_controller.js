import { Controller } from "@hotwired/stimulus"

// Abre e fecha um <dialog> nativo (Gerar de novo na tela de resultado). Quem abre pode preencher a
// observação: "Aceitar sugestão" traz a correção da revisão; "Gerar de novo" abre em branco.
export default class extends Controller {
  static targets = ["dialog", "instructions"]

  open(event) {
    const instructions = event.params?.instructions
    if (this.hasInstructionsTarget && instructions !== undefined) this.instructionsTarget.value = instructions
    this.dialogTarget.showModal()
    if (this.hasInstructionsTarget) this.instructionsTarget.focus()
  }

  close() {
    this.dialogTarget.close()
  }
}
