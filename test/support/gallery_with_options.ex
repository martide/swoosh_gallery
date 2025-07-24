defmodule Support.GalleryWithOptions do
  use Swoosh.Gallery

  # Test preview with direct options
  preview("/direct-options", Support.Emails.OptionsEmail, [locale: "fr"])

  # Test group with options that should be passed to all previews in the group
  group "/localized", title: "Localized Emails", options: [locale: "de"] do
    preview("/welcome", Support.Emails.OptionsEmail)
    preview("/welcome-fr", Support.Emails.OptionsEmail, [locale: "fr"])
  end

  # Test group without options
  group "/default", title: "Default Emails" do
    preview("/welcome", Support.Emails.OptionsEmail)
  end
end
