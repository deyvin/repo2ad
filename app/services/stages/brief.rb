module Stages
  # P1, brief do produto (§5.2): lê o snapshot do repositório e devolve o brief validado.
  #
  #   Stages::Brief.new(meta: {...}, files: [ [ "README.md", "..." ] ], brand_hints: {...},
  #                     images: [ Claude::Stage::Image ], user_photos: [ Claude::Stage::Image ]).call
  class Brief < Claude::Stage
    STAGE = "p1_brief".freeze

    def initialize(meta:, files:, brand_hints:, images: [], user_photos: [], client: Claude::Client.new)
      super(client: client)
      @meta = meta
      @files = files
      @brand_hints = brand_hints
      @images = images
      @user_photos = user_photos
    end

    def user_content
      blocks = [
        text_block("<repo_meta>\n#{JSON.pretty_generate(@meta)}\n</repo_meta>"),
        text_block("<brand_hints>\n#{JSON.pretty_generate(@brand_hints)}\n</brand_hints>")
      ]
      @files.each { |path, content| blocks << repo_file_block(path, content) }
      @images.each { |image| blocks.concat(image_blocks("repo_image", image)) }
      @user_photos.each { |photo| blocks.concat(image_blocks("user_photo", photo)) }
      blocks
    end

    private

    # O kind e a description voltam para os media_inputs pelo path: só vale path de imagem enviada.
    def extra_errors(data)
      return [] unless data.is_a?(Hash)

      known = (@images + @user_photos).map(&:path)
      errors = Array(data["media"]).filter_map do |item|
        path = item.is_a?(Hash) ? item["path"] : nil
        "/media: path #{path.inspect} is not one of the provided images (#{known.join(", ")})" unless known.include?(path)
      end
      logo = data.dig("brand", "logo_media_path")
      errors << "/brand/logo_media_path: #{logo.inspect} is not one of the provided images" if logo && !known.include?(logo)
      errors
    end
  end
end
