# Tela Novo projeto (§2) e tela de análise. O create valida e guarda; a ingestão roda no IngestRepoJob.
class ProjectsController < ApplicationController
  MAX_PHOTOS = 8
  PHOTO_EXTENSIONS = %w[.jpg .jpeg .png .heic .heif].freeze

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(repo_url: project_params[:repo_url].to_s.strip)
    photos = uploaded_photos

    validate_repo_url
    validate_photos(photos)
    return render :new, status: :unprocessable_entity if @project.errors.any?

    Project.transaction do
      @project.save!
      photos.each { |photo| attach_photo(photo) }
    end
    IngestRepoJob.perform_later(@project.id)
    redirect_to project_path(@project)
  end

  def show
    @project = Project.find(params[:id])
  end

  private

  def project_params
    params.fetch(:project, {}).permit(:repo_url, photos: [])
  end

  def uploaded_photos
    Array(project_params[:photos]).select { |photo| photo.respond_to?(:original_filename) }
  end

  def validate_repo_url
    Repo::Url.new(@project.repo_url)
  rescue Repo::Error => e
    @project.errors.add(:repo_url, e.message)
  end

  def validate_photos(photos)
    if photos.size > MAX_PHOTOS
      @project.errors.add(:photos, "Envie até #{MAX_PHOTOS} fotos.")
    elsif photos.any? { |photo| PHOTO_EXTENSIONS.exclude?(File.extname(photo.original_filename).downcase) }
      @project.errors.add(:photos, "Formato não aceito: use JPG, PNG ou HEIC.")
    end
  end

  # O arquivo original fica guardado; a normalização (HEIC para JPEG, EXIF, 1568 px) é feita no IngestRepoJob.
  def attach_photo(photo)
    @project.media_inputs.create!(source: "upload").file.attach(photo)
  end
end
