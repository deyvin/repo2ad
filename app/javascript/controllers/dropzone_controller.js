import { Controller } from "@hotwired/stimulus"

// Dropzone das fotos: arrastar e soltar sobre a área entrega os arquivos ao campo de arquivo,
// que continua sendo o que o formulário envia. Antes de enviar, confere a quantidade e o formato;
// o servidor valida de novo. Sem JavaScript, o campo funciona do mesmo jeito.
const MAX_PHOTOS = 8
const ACCEPTED = /\.(jpe?g|png|heic|heif)$/i

export default class extends Controller {
  static targets = ["input", "list", "error"]

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
    const files = Array.from(this.inputTarget.files)
    const problem = this.problemWith(files)

    this.errorTarget.textContent = problem
    this.errorTarget.classList.toggle("hidden", !problem)

    if (problem) {
      this.inputTarget.value = ""
      this.listTarget.textContent = ""
      return
    }
    this.listTarget.textContent = files.length ? `${files.length} foto(s) escolhida(s)` : ""
  }

  problemWith(files) {
    if (files.length > MAX_PHOTOS) return `Envie até ${MAX_PHOTOS} fotos.`
    if (files.some((file) => !ACCEPTED.test(file.name))) return "Formato não aceito: use JPG, PNG ou HEIC."
    return ""
  }
}
