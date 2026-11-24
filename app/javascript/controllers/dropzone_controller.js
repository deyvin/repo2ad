import { Controller } from "@hotwired/stimulus"

// Dropzone das fotos: arrastar e soltar sobre a área entrega os arquivos ao campo de arquivo,
// que continua sendo o que o formulário envia. Sem JavaScript, o campo funciona do mesmo jeito.
export default class extends Controller {
  static targets = ["input", "list"]

  over(event) {
    event.preventDefault()
    this.element.classList.add("border-magenta")
  }

  leave() {
    this.element.classList.remove("border-magenta")
  }

  drop(event) {
    event.preventDefault()
    this.leave()
    if (event.dataTransfer?.files?.length) {
      this.inputTarget.files = event.dataTransfer.files
      this.show()
    }
  }

  show() {
    const count = this.inputTarget.files.length
    this.listTarget.textContent = count ? `${count} foto(s) escolhida(s)` : ""
  }
}
