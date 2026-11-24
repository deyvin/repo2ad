module Higgsfield
  # Gateway de mentira para testes (e para desenvolvimento sem gastar créditos). Grava as chamadas e
  # responde a cada job com uma sequência de status programada; nada sai da máquina.
  #
  #   fake = Higgsfield::FakeGateway.new(result_path: "frame.png")
  #   job_id = fake.submit(model: "kling4_0", prompt: "...")
  #   fake.script(job_id, :running, :running, :done)
  class FakeGateway
    include Gateway

    attr_reader :calls, :uploads, :submissions
    attr_accessor :credits

    def initialize(result_path: nil, credits: 1000.0, cost: 2.0)
      @result_path = result_path
      @credits = credits
      @cost = cost
      @calls = []
      @uploads = []
      @submissions = []
      @scripts = Hash.new { |hash, key| hash[key] = [] }
      @sequence = 0
    end

    # Próximos status de um job: :running, :done, :failed, uma String (falha com essa mensagem)
    # ou uma exceção (levantada na consulta).
    def script(job_id, *states)
      @scripts[job_id].concat(states)
      self
    end

    def upload(path, content_type: nil)
      @calls << [ :upload, path.to_s ]
      @uploads << path.to_s
      "fake-media-#{next_id}"
    end

    def submit(model:, prompt:, params: {}, media: [])
      @calls << [ :submit, model ]
      job_id = "fake-job-#{next_id}"
      @submissions << { job_id: job_id, model: model, prompt: prompt, params: params, media: media }
      job_id
    end

    def status(job_id)
      @calls << [ :status, job_id ]
      state = @scripts[job_id].shift || :done
      case state
      when Exception, Class then raise state
      when :running then Gateway::Status.new(state: :running, result_url: nil, error: nil, poll_after: nil)
      when :done then Gateway::Status.new(state: :done, result_url: "https://cdn.fake.test/#{job_id}.png", error: nil, poll_after: nil)
      when String then Gateway::Status.new(state: :failed, result_url: nil, error: state, poll_after: nil)
      else Gateway::Status.new(state: :failed, result_url: nil, error: "A Higgsfield não conseguiu gerar o resultado.", poll_after: nil)
      end
    end

    def cost(model:, prompt: nil, params: {}, media: [])
      @calls << [ :cost, model ]
      @cost
    end

    def balance
      @calls << [ :balance ]
      { credits: @credits, plan: "fake" }
    end

    def download(url)
      @calls << [ :download, url ]
      raise ConfigurationError, "FakeGateway sem result_path para baixar #{url}" unless @result_path

      Gateway::Download.new(io: File.open(@result_path, "rb"), content_type: Marcel::MimeType.for(Pathname.new(@result_path)),
                            filename: File.basename(@result_path))
    end

    private

    def next_id
      @sequence += 1
    end
  end
end
