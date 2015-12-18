class Projects::ArtifactsController < Projects::ApplicationController
  layout 'project'
  before_action :authorize_download_build_artifacts!

  def download
    unless artifacts_file.file_storage?
      return redirect_to artifacts_file.url
    end

    unless artifacts_file.exists?
      return not_found!
    end

    send_file artifacts_file.path, disposition: 'attachment'
  end

  def browse
    path = params[:path].to_s
    @paths = artifacts_metadata.map do |_artifact_file|
      Gitlab::StringPath.new(path, artifacts_metadata)
    end
  end

  private

  def build
    @build ||= project.builds.unscoped.find_by!(id: params[:build_id])
  end

  def artifacts_file
    @artifacts_file ||= build.artifacts_file
  end

  def artifacts_metadata
    @artifacts_metadata ||= build.artifacts_metadata
  end

  def authorize_download_build_artifacts!
    unless can?(current_user, :download_build_artifacts, @project)
      if current_user.nil?
        return authenticate_user!
      else
        return render_404
      end
    end
  end
end
