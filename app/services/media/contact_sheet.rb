require "fileutils"
require "open3"
require "securerandom"

module Media
  # Gera uma grade JPEG com quadros do vídeo, cada um com o instante escrito (ffmpeg drawtext).
  # A célula segue o aspecto do vídeo, com o lado maior em LONG_SIDE px; a grade tem até 4 colunas.
  class ContactSheet
    class Error < StandardError; end

    Result = Data.define(:path, :timestamps)

    TIMESTAMPS = [ 0.5, 2.5, 4.0, 5.5, 7.0, 8.5, 9.7 ].freeze
    COLUMNS = 4
    LONG_SIDE = 480

    def self.call(video_path, output_path: nil)
      new(video_path, output_path: output_path).call
    end

    def initialize(video_path, output_path: nil)
      @video_path = video_path.to_s
      @output_path = output_path ? output_path.to_s : default_output_path
    end

    def call
      probe = Media::Probe.call(@video_path)
      raise Error, "o arquivo não é um vídeo" if probe.duration.nil?

      timestamps = TIMESTAMPS.select { |t| t < probe.duration }
      raise Error, "vídeo curto demais para a contact sheet" if timestamps.empty?

      cell_width, cell_height = cell_size(probe.width, probe.height)
      FileUtils.mkdir_p(File.dirname(@output_path))
      run_ffmpeg(timestamps, cell_width, cell_height)
      Result.new(path: @output_path, timestamps: timestamps)
    end

    private

    def cell_size(width, height)
      if width >= height
        [ LONG_SIDE, even(LONG_SIDE * height.to_f / width) ]
      else
        [ even(LONG_SIDE * width.to_f / height), LONG_SIDE ]
      end
    end

    # yuv420 exige dimensões pares.
    def even(value)
      2 * (value / 2.0).round
    end

    def run_ffmpeg(timestamps, cell_width, cell_height)
      cols = [ timestamps.size, COLUMNS ].min
      filter = filter_graph(timestamps, cols, cell_width, cell_height)

      args = [ "ffmpeg", "-hide_banner", "-loglevel", "error", "-y" ]
      timestamps.each { |t| args += [ "-ss", format("%.1f", t), "-i", @video_path ] }
      args += [ "-filter_complex", filter, "-map", "[grid]", "-frames:v", "1", "-update", "1", @output_path ]

      _out, _err, status = Open3.capture3(*args)
      raise Error, "falha ao gerar a contact sheet" unless status.success?
    rescue Errno::ENOENT
      raise Error, "ffmpeg não está instalado"
    end

    # Cada entrada vira uma célula: primeiro quadro após o seek, encaixado no tamanho da célula, com o instante no canto.
    # fill=black: células sem quadro saem pretas, não com lixo de memória.
    def filter_graph(timestamps, cols, cell_width, cell_height)
      branches = timestamps.each_with_index.map do |t, i|
        "[#{i}:v]select='eq(n,0)'," \
          "scale=#{cell_width}:#{cell_height}:force_original_aspect_ratio=decrease," \
          "pad=#{cell_width}:#{cell_height}:(ow-iw)/2:(oh-ih)/2:black," \
          "drawtext=text='#{format("%.1f s", t)}':fontcolor=white:fontsize=28:" \
          "box=1:boxcolor=black@0.6:boxborderw=8:x=12:y=12[c#{i}]"
      end

      layout = timestamps.each_index.map do |i|
        "#{(i % cols) * cell_width}_#{(i / cols) * cell_height}"
      end.join("|")
      inputs = timestamps.each_index.map { |i| "[c#{i}]" }.join

      "#{branches.join(';')};#{inputs}xstack=inputs=#{timestamps.size}:layout=#{layout}:fill=black[grid]"
    end

    def default_output_path
      name = "#{File.basename(@video_path, '.*')}-#{SecureRandom.hex(4)}.jpg"
      Rails.root.join("tmp", "contact_sheets", name).to_s
    end
  end
end
