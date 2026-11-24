require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  test "new shows the repository form" do
    get new_project_path

    assert_response :success
    assert_select "h1", "Qual repositório vamos anunciar?"
    assert_select "input[type=url][name=repo_url]"
  end

  test "root goes to the new project screen" do
    get root_path

    assert_response :success
    assert_select "h1", "Qual repositório vamos anunciar?"
  end
end
