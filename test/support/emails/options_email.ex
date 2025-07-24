defmodule Support.Emails.OptionsEmail do
  import Swoosh.Email

  # This function will be called when no options are provided (backward compatibility)
  def preview() do
    preview([])
  end

  # This function will be called when options are provided
  def preview(options) when is_list(options) do
    locale = Keyword.get(options, :locale, "en")
    subject_text = case locale do
      "fr" -> "Bonjour"
      "de" -> "Hallo"
      _ -> "Hello"
    end

    new()
    |> subject(subject_text)
    |> html_body("Welcome with options: #{inspect(options)}")
  end

  # This function will be called when no options are provided (backward compatibility)
  def preview_details() do
    preview_details([])
  end

  # This function will be called when options are provided
  def preview_details(options) when is_list(options) do
    locale = Keyword.get(options, :locale, "en")
    title = case locale do
      "fr" -> "Email avec Options"
      "de" -> "Email mit Optionen"
      _ -> "Email with Options"
    end

    [
      title: title,
      description: "Email that supports options: #{inspect(options)}",
      tags: [locale: locale, options: "yes"]
    ]
  end
end
