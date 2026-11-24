import { Controller } from "@hotwired/stimulus"

// Seleção do cardápio: conta os criativos marcados, soma os créditos estimados e mostra o total no botão Gerar.
// Só deixa Gerar ligado com pelo menos um criativo. Sem estimativa de algum marcado, o botão diz só "Gerar".
export default class extends Controller {
  static targets = ["checkbox", "count", "submit"]

  connect() {
    this.update()
  }

  update() {
    const boxes = this.checkboxTargets.filter((box) => box.checked)
    const known = boxes.every((box) => box.dataset.credits !== "")
    const total = boxes.reduce((sum, box) => sum + (Number(box.dataset.credits) || 0), 0)

    if (this.hasCountTarget) this.countTarget.textContent = `${boxes.length} selecionado(s)`
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = boxes.length === 0
      this.submitTarget.value = boxes.length && known
        ? `Gerar (≈ ${total.toLocaleString("pt-BR", { maximumFractionDigits: 2 })} créditos)`
        : "Gerar"
    }
  }
}
