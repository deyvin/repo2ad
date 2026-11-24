module Higgsfield
  # Interface de geração da Higgsfield usada pelas receitas e pelo PollRenderStepJob (D1, decisão 006).
  #
  #   gateway = Higgsfield::Gateway.current
  #   media_id = gateway.upload("start.png")
  #   job_id = gateway.submit(model: "kling4_0", prompt: "...", params: { aspect_ratio: "16:9", duration: 10 },
  #                           media: [ { value: media_id, role: "start_image" }, { value: end_job_id, role: "end_image" } ])
  #   gateway.status(job_id)  # => Gateway::Status(state: :running | :done | :failed, ...)
  #   gateway.download(url)   # => Gateway::Download(io:, content_type:, filename:)
  #
  # media[].value é o media_id de um upload ou o job_id de um step anterior (encadeia sem baixar e subir de novo).
  module Gateway
    MODELS = %w[nano_banana_2_1 kling4_0].freeze

    # state: :running (continua consultando), :done (result_url pronto) ou :failed (error em português).
    # poll_after: segundos sugeridos pela Higgsfield até a próxima consulta (pode ser nil).
    Status = Data.define(:state, :result_url, :error, :poll_after) do
      def running? = state == :running
      def done? = state == :done
      def failed? = state == :failed
    end

    Download = Data.define(:io, :content_type, :filename)

    class << self
      attr_writer :current

      # Implementação em uso; os testes trocam por um FakeGateway.
      def current
        @current || McpGateway.new
      end
    end

    # Métodos que toda implementação oferece.
    def upload(path, content_type: nil) = raise(NotImplementedError)
    def submit(model:, prompt:, params: {}, media: []) = raise(NotImplementedError)
    def status(job_id) = raise(NotImplementedError)
    def cost(model:, prompt: nil, params: {}, media: []) = raise(NotImplementedError)
    def balance = raise(NotImplementedError)
    def download(url) = raise(NotImplementedError)
  end
end
