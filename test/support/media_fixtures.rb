require "fileutils"
require "open3"

# Gera mídia sintética com ffmpeg (lavfi), sem arquivos binários no repositório e sem rede.
module MediaFixtures
  def make_video(dir, name, size:, duration:, extra: [])
    path = File.join(dir, name)
    ffmpeg("-f", "lavfi", "-i", "testsrc=size=#{size}:rate=10:duration=#{duration}",
           "-c:v", "mpeg4", "-q:v", "5", *extra, path)
    path
  end

  def make_image(dir, name, size:)
    path = File.join(dir, name)
    ffmpeg("-f", "lavfi", "-i", "testsrc=size=#{size}", "-frames:v", "1", path)
    path
  end

  def ffmpeg(*args)
    _out, err, status = Open3.capture3("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args)
    raise "ffmpeg falhou: #{err}" unless status.success?
  end

  def jpeg?(path)
    File.binread(path, 2) == "\xFF\xD8".b
  end
end
