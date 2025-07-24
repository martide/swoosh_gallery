defmodule Swoosh.GalleryTest do
  use ExUnit.Case
  import Plug.Test

  alias Support.Router

  Router.init([])

  describe "previews/0" do
    test "returns the list of previews" do
      assert previews = Support.Gallery.get()

      assert %{
               previews: [
                 %{
                   preview_details: %{
                     description: "Sends instructions on how to reset password",
                     tags: [passwords: "yes"],
                     title: "Reset Password"
                   },
                   path: "auth.reset_password",
                   email_mfa: {Support.Emails.ResetPasswordEmail, :preview, []},
                   group: "auth"
                 },
                 %{
                   preview_details: %{
                     description: "Sends a warm welcome to the user",
                     tags: [attachments: "yes"],
                     title: "Welcome"
                   },
                   path: "welcome",
                   email_mfa: {Support.Emails.WelcomeEmail, :preview, []},
                   group: nil
                 }
               ],
               groups: [%{path: "auth", title: "Auth"}]
             } = previews
    end
  end

  describe "options functionality" do
    test "preview with direct options" do
      assert previews = Support.GalleryWithOptions.get()

      direct_options_preview = Enum.find(previews.previews, fn %{path: path} -> path == "direct-options" end)
      assert direct_options_preview
      assert direct_options_preview.email_mfa == {Support.Emails.OptionsEmail, :preview, [locale: "fr"]}
      assert direct_options_preview.details_mfa == {Support.Emails.OptionsEmail, :preview_details, [locale: "fr"]}
    end

    test "group with options passes options to previews" do
      assert previews = Support.GalleryWithOptions.get()

      # Preview in group without explicit options should inherit group options
      group_preview = Enum.find(previews.previews, fn %{path: path} -> path == "localized.welcome" end)
      assert group_preview
      assert group_preview.email_mfa == {Support.Emails.OptionsEmail, :preview, [locale: "de"]}
      assert group_preview.details_mfa == {Support.Emails.OptionsEmail, :preview_details, [locale: "de"]}

      # Preview in group with explicit options should merge group and preview options
      group_preview_with_options = Enum.find(previews.previews, fn %{path: path} -> path == "localized.welcome-fr" end)
      assert group_preview_with_options
      assert group_preview_with_options.email_mfa == {Support.Emails.OptionsEmail, :preview, [locale: "fr", locale: "de"]}
      assert group_preview_with_options.details_mfa == {Support.Emails.OptionsEmail, :preview_details, [locale: "fr", locale: "de"]}
    end

    test "group without options passes empty options" do
      assert previews = Support.GalleryWithOptions.get()

      default_preview = Enum.find(previews.previews, fn %{path: path} -> path == "default.welcome" end)
      assert default_preview
      assert default_preview.email_mfa == {Support.Emails.OptionsEmail, :preview, []}
      assert default_preview.details_mfa == {Support.Emails.OptionsEmail, :preview_details, []}
    end

    test "groups structure includes all groups" do
      assert previews = Support.GalleryWithOptions.get()

      assert length(previews.groups) == 2

      localized_group = Enum.find(previews.groups, fn %{path: path} -> path == "localized" end)
      assert localized_group
      assert localized_group.title == "Localized Emails"

      default_group = Enum.find(previews.groups, fn %{path: path} -> path == "default" end)
      assert default_group
      assert default_group.title == "Default Emails"
    end
  end

  describe "sort option" do
    test "when is not set, returns the default true" do
      assert %{sort: true} = Support.Gallery.get()
    end

    test "when is set to false, returns false" do
      assert %{sort: false} = Support.GallerySortFalse.get()
    end

    test "when is set to a function, returns the function" do
      assert %{sort: sort_function} = Support.GallerySortIsAFunction.get()
      assert is_function(sort_function)
      assert "#{inspect(sort_function)}" == "&Support.GallerySortIsAFunction.sort/1"
    end
  end

  describe "Gallery plug" do
    test "lists preview titles" do
      response = Router.call(conn(:get, "/gallery"), [])
      assert response.status == 200
      assert response.resp_body =~ "Reset Password"
      assert response.resp_body =~ "Welcome"
    end

    test "has links to the previews" do
      response = Router.call(conn(:get, "/gallery"), [])
      assert response.status == 200
      assert response.resp_body =~ "a href=\"/gallery/auth.reset_password\""
      assert response.resp_body =~ "a href=\"/gallery/welcome\""
    end

    test "accessing a preview lists the basic informations" do
      response = Router.call(conn(:get, "/gallery/welcome"), [])
      assert response.status == 200
      assert response.resp_body =~ "Welcome"
      assert response.resp_body =~ "Sends a warm welcome to the user"
      assert response.resp_body =~ "attachments: yes"
    end

    test "accessing a preview shows the email as text" do
      response = Router.call(conn(:get, "/gallery/auth.reset_password"), [])
      assert response.status == 200
      assert response.resp_body =~ "Reset Password"
      assert response.resp_body =~ "Sends instructions on how to reset password"
      assert response.resp_body =~ "passwords: yes"
      assert response.resp_body =~ "Please, reset your password: http://reset.pw"
    end

    test "accessing a preview.html shows the email as html" do
      response = Router.call(conn(:get, "/gallery/auth.reset_password/preview.html"), [])
      assert response.status == 200

      assert response.resp_body ==
               "Please, reset your password <a href=\"http://reset.pw\">here</a>."
    end
  end
end
