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

  # Lê um pixel (RGB) de uma imagem. format=rgb24 vem antes do crop: em yuv420 um crop de 1x1 zera a crominância.
  def pixel_at(path, x, y)
    out, err, status = Open3.capture3("ffmpeg", "-hide_banner", "-loglevel", "error", "-i", path,
                                      "-vf", "format=rgb24,crop=1:1:#{x}:#{y}", "-frames:v", "1",
                                      "-f", "rawvideo", "-pix_fmt", "rgb24", "-")
    raise "ffmpeg falhou ao ler o pixel: #{err}" unless status.success?

    out.unpack("C3")
  end

  def jpeg?(path)
    File.binread(path, 2) == "\xFF\xD8".b
  end
end
