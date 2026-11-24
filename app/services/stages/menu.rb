module Stages
  # P3, cardápio de criativos (§5.4): 10 a 12 itens, cada um com uma receita, formato e mídia do brief.
  #
  #   Stages::Menu.new(brief: ..., audience: ..., angles: ..., media_inventory: [...], client: client).call
  class Menu < Claude::Stage
    STAGE = "p3_menu".freeze

    def initialize(brief:, audience:, angles:, media_inventory:, client: Claude::Client.new)
      super(client: client)
      @brief = brief
      @audience = audience
      @angles = angles
      @media_inventory = media_inventory
    end

    def user_content
      [
        text_block("<brief>\n#{JSON.pretty_generate(@brief)}\n</brief>"),
        text_block("<audience>\n#{JSON.pretty_generate(@audience)}\n</audience>"),
        text_block("<angles>\n#{JSON.pretty_generate(@angles)}\n</angles>"),
        text_block("<media_inventory>\n#{JSON.pretty_generate(@media_inventory)}\n</media_inventory>")
      ]
    end

    private

    # Regras do §5.4 que o schema não expressa: grupo x receita x duração x formato, e mídias que existem.
    def extra_errors(data)
      return [] unless data.is_a?(Hash) && data["items"].is_a?(Array)

      known = @media_inventory.map { |media| media[:path] }
      data["items"].each_with_index.flat_map do |item, index|
        next [] unless item.is_a?(Hash)

        where = "/items/#{index}"
        errors = []
        case item["group"]
        when "image"
          errors << "#{where}: image items must use recipe nb_image" unless item["recipe"] == "nb_image"
          errors << "#{where}: image items must have duration_seconds null" unless item["duration_seconds"].nil?
        when "vertical"
          errors << "#{where}: vertical items must use aspect_ratio 9:16" unless item["aspect_ratio"] == "9:16"
        when "horizontal"
          errors << "#{where}: horizontal items must use aspect_ratio 16:9" unless item["aspect_ratio"] == "16:9"
        end
        Array(item["media_paths"]).each do |path|
          errors << "#{where}: media_paths #{path.inspect} is not in media_inputs" unless known.include?(path)
        end
        errors
      end
    end
  end
end
