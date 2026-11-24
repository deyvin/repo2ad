require "test_helper"

module Costs
  # FakeGateway que também guarda os params de cada cost (o FakeGateway só conta a chamada).
  class RecordingGateway < Higgsfield::FakeGateway
    def cost(model:, prompt: nil, params: {}, media: [])
      cost_calls << { model: model, params: params }
      super
    end

    def cost_calls
      @cost_calls ||= []
    end
  end

  class EstimatorTest < ActiveSupport::TestCase
    setup do
      @project = Project.create!(repo_url: "https://github.com/deyvin/cabide")
      @gateway = RecordingGateway.new(cost: 2.0)
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    teardown do
      Rails.cache = @original_cache
    end

    test "nb_image: um Nano Banana com o aspecto do creative, 2k e high" do
      creative = build_creative(recipe: "nb_image", aspect_ratio: "4:5", duration: nil)

      result = Estimator.for(creative, gateway: @gateway)

      assert_equal 1, result.steps.size
      assert_equal 2.0, result.total
      assert_equal "nano_banana_2_1", @gateway.cost_calls.first[:model]
      assert_equal({ aspect_ratio: "4:5", resolution: "2k", thinking_level: "high" }, @gateway.cost_calls.first[:params])
    end

    test "kling_magic: Nano Banana do quadro inicial mais Kling image-to-video na duração do creative" do
      creative = build_creative(recipe: "kling_magic", aspect_ratio: "9:16", duration: 10)

      result = Estimator.for(creative, gateway: @gateway)

      assert_equal 2, result.steps.size
      assert_equal 4.0, result.total
      kling = @gateway.cost_calls.last
      assert_equal "kling4_0", kling[:model]
      assert_equal({ aspect_ratio: "9:16", duration: 10, resolution: "1080p", mode: "image-to-video" }, kling[:params])
    end

    test "kling_keyframes: compose não gera chamada, só Nano Banana do quadro final e Kling" do
      creative = build_creative(recipe: "kling_keyframes", aspect_ratio: "16:9", duration: 5)

      result = Estimator.for(creative, gateway: @gateway)

      assert_equal %w[start_frame end_frame main], result.steps.map(&:name)
      assert_equal 0.0, result.steps.first.credits
      assert_equal 2, @gateway.cost_calls.size
      assert_equal 4.0, result.total
      assert_equal 5, @gateway.cost_calls.last[:params][:duration]
    end

    test "com spec (P4), usa os steps reais e tira params nulos" do
      creative = build_creative(recipe: "kling_magic", aspect_ratio: "16:9", duration: 10)
      creative.update!(spec: { "steps" => [
        { "name" => "main", "kind" => "kling", "model" => "kling4_0",
          "params" => { "aspect_ratio" => "16:9", "duration" => 10, "resolution" => "1080p",
                        "mode" => "image-to-video", "thinking_level" => nil } }
      ] })

      result = Estimator.for(creative, gateway: @gateway)

      assert_equal [ "main" ], result.steps.map(&:name)
      assert_equal 1, @gateway.cost_calls.size
      assert_equal({ aspect_ratio: "16:9", duration: 10, resolution: "1080p", mode: "image-to-video" },
                   @gateway.cost_calls.first[:params])
    end

    test "a estimativa fica em cache por params: a segunda chamada não vai ao gateway" do
      creative = build_creative(recipe: "nb_image", aspect_ratio: "4:5", duration: nil)

      Estimator.for(creative, gateway: @gateway)
      Estimator.for(creative, gateway: @gateway)

      assert_equal 1, @gateway.cost_calls.size
    end

    test "for_selection soma só os creatives marcados e traz o detalhe de cada um" do
      build_creative(code: "I1", recipe: "nb_image", aspect_ratio: "4:5", selected: true)
      build_creative(code: "V1", recipe: "kling_magic", aspect_ratio: "9:16", duration: 10, selected: false)
      build_creative(code: "I2", recipe: "nb_image", aspect_ratio: "1:1", selected: true)

      selection = Estimator.for_selection(@project, gateway: @gateway)

      assert_equal 4.0, selection.total
      assert_equal %w[I1 I2], selection.creatives.map { |entry| entry.creative.code }
      assert_equal [ 2.0, 2.0 ], selection.creatives.map(&:total)
    end

    private

    def build_creative(code: "I1", selected: false, **attrs)
      Creative.create!({ project: @project, code: code, group: "image", status: "proposed",
                         selected: selected }.merge(attrs))
    end
  end
end
