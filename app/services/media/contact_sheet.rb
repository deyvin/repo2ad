require "fileutils"
require "open3"
require "securerandom"

module Media
  # Gera uma grade JPEG com quadros do vídeo, cada um com o instante escrito (ffmpeg drawtext).
  class ContactSheet
    class Error < StandardError; end

    Result = Data.define(:path, :timestamps)

    TIMESTAMPS = [ 0.5, 2.5, 4.0, 5.5, 7.0, 8.5, 9.7 ].freeze
    COLUMNS = 4
    CELL_WIDTH = 270
    CELL_HEIGHT = 480

    def self.call(video_path, output_path: nil)
      new(video_path, output_path: output_path).call
    end

    def initialize(video_path, output_path: nil)
      @video_path = video_path.to_s
      @output_path = output_path ? output_path.to_s : default_output_path
    end

    def call
      duration = Media::Probe.call(@video_path).duration
      raise Error, "não consegui medir a duração do vídeo" if duration.nil?

      timestamps = TIMESTAMPS.select { |t| t < duration }
      raise Error, "vídeo curto demais para a contact sheet" if timestamps.empty?

      FileUtils.mkdir_p(File.dirname(@output_path))
      run_ffmpeg(timestamps)
      Result.new(path: @output_path, timestamps: timestamps)
    end

    private

    def run_ffmpeg(timestamps)
      cols = [ timestamps.size, COLUMNS ].min

      args = [ "ffmpeg", "-hide_banner", "-loglevel", "error", "-y" ]
      timestamps.each { |t| args += [ "-ss", format("%.1f", t), "-i", @video_path ] }
      args += [ "-filter_complex", filter_graph(timestamps, cols), "-map", "[grid]",
               "-frames:v", "1", "-update", "1", @output_path ]

      _out, _err, status = Open3.capture3(*args)
      raise Error, "falha ao gerar a contact sheet" unless status.success?
    rescue Errno::ENOENT
      raise Error, "ffmpeg não está instalado"
    end

    # Cada entrada vira uma célula: primeiro quadro após o seek, encaixado em 270x480 e com o instante no canto.
    def filter_graph(timestamps, cols)
      branches = timestamps.each_with_index.map do |t, i|
        "[#{i}:v]select='eq(n,0)'," \
          "scale=#{CELL_WIDTH}:#{CELL_HEIGHT}:force_original_aspect_ratio=decrease," \
          "pad=#{CELL_WIDTH}:#{CELL_HEIGHT}:(ow-iw)/2:(oh-ih)/2:black," \
          "drawtext=text='#{format("%.1f s", t)}':fontcolor=white:fontsize=28:" \
          "box=1:boxcolor=black@0.6:boxborderw=8:x=12:y=12[c#{i}]"
      end

      layout = timestamps.each_index.map do |i|
        "#{(i % cols) * CELL_WIDTH}_#{(i / cols) * CELL_HEIGHT}"
      end.join("|")
      inputs = timestamps.each_index.map { |i| "[c#{i}]" }.join

      "#{branches.join(';')};#{inputs}xstack=inputs=#{timestamps.size}:layout=#{layout}[grid]"
    end

    def default_output_path
      name = "#{File.basename(@video_path, '.*')}-#{SecureRandom.hex(4)}.jpg"
      Rails.root.join("tmp", "contact_sheets", name).to_s
    end
  end
end
