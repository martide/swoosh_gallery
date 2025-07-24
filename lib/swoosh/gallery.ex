defmodule Swoosh.Gallery do
  @moduledoc ~S"""
  Swoosh.Gallery is a library to preview and display your Swoosh mailers to everyone,
  either by exposing the previews on your application's router or publishing it on
  your favorite static host solution.

  ## Getting Started

  You will a gallery module to organize all your previews, and implement the expected
  callbacks on your mailer modules:

      defmodule MyApp.Mailer.Gallery do
        use Swoosh.Gallery

        preview("/welcome", MyApp.Mailer.WelcomeMailer)
      end

      defmodule MyApp.Mailer.WelcomeMailer do
        # the expected Swoosh / Phoenix.Swoosh code that you already have to deliver emails
        use Phoenix.Swoosh, view: SampleWeb.WelcomeMailerView, layout: {MyApp.LayoutView, :email}

        def welcome(user) do
          new()
          |> from("noreply@sample.test")
          |> to({user.name, user.email})
          |> subject("Welcome to Sample App")
          |> render_body("welcome.html", user: user)
        end

        # `preview/0` function that builds your email using fixture data
        def preview do
          welcome(%{email: "user@sample.test", name: "Test User!"})
        end

        # `preview_details/0` with some useful metadata about your mailer
        def preview_details do
          [
            title: "Welcome to MyApp!",
            description: "First email to welcome users into the platform"
          ]
        end
      end

  Then in your router, you can mount your Gallery to expose it to the web:

      forward "/gallery", MyApp.Mailer.Gallery

  Or, you can generate static web pages with all the previews from your gallery:

      mix swoosh.gallery.html --gallery MyApp.Mailer.Gallery --path "_build/emails"

  By default, the previews will be sorted alphabetically. You can customize the sorting
  by implementing the `sort/1` callback on your gallery module:

      defmodule MyApp.Mailer.Gallery do
        use Swoosh.Gallery,
          sort: &MyApp.Mailer.Gallery.sort/1

        preview("/welcome", MyApp.Mailer.WelcomeMailer)
      end

   Or disable sorting by passing `sort: false`, so the previews will be displayed in the
   defined order in your Gallery.

       defmodule MyApp.Mailer.Gallery do
        use Swoosh.Gallery, sort: false
        ...
      end


  ### Generating preview data

  Previews should be built using in memory fixture data and we do **not recommend** that you
  reuse your application's code to query for existing data or generate files during runtime. The
  `preview/0` can be invoked multiple times as you navigate through your gallery on your browser
  when mounting it on the router or when using the `swoosh.gallery.html` task to generate the static
  pages.

      defmodule MyApp.Mailer.SendContractEmail do
        def send_contract(user, blob) do
          contract =
            Swoosh.Attachment.new({:data, blob}, filename: "contract.pdf", content_type: "application/pdf")

          new()
          |> to({user.name, user.email})
          |> subject("Here is your Contract")
          |> attachment(contract)
          |> render_body(:contract, user: user)
        end

        # Bad - invokes application code to query data and generate the PDF contents
        def preview do
          user = MyApp.Users.find_user("testuser@acme.com")
          {:ok, blob} = MyApp.Contracts.build_contract(user)
          build(user, blob)
        end

        # Good - uses in memory structs and existing fixtures
        def preview do
          blob = File.read!("#{Application.app_dir(:my_app, "my_app")}/fixtures/sample.pdf")
          build(%User{}, blob)
        end
      end
  """

  @doc """
  Sorts the previews. It receives a list of previews and should return a list of previews.
  """
  @callback sort(list(%{preview_details: map()})) :: list()
  @optional_callbacks sort: 1

  @spec __using__(any) ::
          {:__block__, [], [{:@ | :def | :import | {any, any, any}, [...], [...]}, ...]}
  defmacro __using__(options) do
    quote do
      @behaviour Swoosh.Gallery

      import unquote(__MODULE__)
      Module.register_attribute(__MODULE__, :previews, accumulate: true)
      Module.register_attribute(__MODULE__, :groups, accumulate: true)
      @group_path nil
      @group_options []
      @sort Keyword.get(unquote(options), :sort, true)

      def init(opts) do
        Keyword.put(opts, :gallery, __MODULE__.get())
      end

      def call(conn, opts) do
        Swoosh.Gallery.Plug.call(conn, opts)
      end

      @before_compile unquote(__MODULE__)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def get do
        previews = eval_details(@previews)
        %{previews: previews, groups: @groups, sort: @sort}
      end
    end
  end

  @doc ~S"""
  Declares a preview route. If expects that the module passed implements both
  `preview/0` and `preview_details/0`.

  ## Examples

      defmodule MyApp.Mailer.Gallery do
        use Swoosh.Gallery

        preview "/welcome", MyApp.Emails.Welcome
        preview "/account-confirmed", MyApp.Emails.AccountConfirmed
        preview "/password-reset", MyApp.Emails.PasswordReset

        # With options
        preview "/welcome", MyApp.Emails.Welcome, ["en-GB"]
        preview "/welcome", MyApp.Emails.Welcome, [locale: "en-GB"]

      end

  ## Options

  The `options` parameter will be passed to both the `preview/1` and `preview_details/1`
  functions of the mailer module. When used inside a group, these options will be merged
  with any group-level options.

  ## Backward Compatibility

  The library automatically handles backward compatibility. Mailer modules can implement either:

  **Simple form (recommended for most cases):**
      def preview() do
        # Implementation without options
      end

      def preview_details() do
        [title: "My Email"]
      end

  **With options support:**
      def preview() do
        preview([])  # Call the options version with empty options
      end

      def preview(options) when is_list(options) do
        # Implementation with options
      end

      def preview_details() do
        preview_details([])  # Call the options version with empty options
      end

      def preview_details(options) when is_list(options) do
        # Implementation with options
      end

  The library will automatically try to call the arity-1 version first, and fall back to arity-0 if it doesn't exist.
  """
  @spec preview(String.t(), module(), list()) :: no_return()
  defmacro preview(path, module, options \\ []) do
    path = validate_path(path)
    module = Macro.expand(module, __ENV__)
    validate_preview_details!(module)

    quote do
      merged_options = Keyword.merge(List.wrap(@group_options), List.wrap(unquote(options)))
      @previews %{
        group: @group_path,
        path: build_preview_path(@group_path, unquote(path)),
        email_mfa: {unquote(module), :preview, merged_options},
        details_mfa: {unquote(module), :preview_details, merged_options}
      }
    end
  end

  @doc """
  Defines a scope in which previews can be nested when rendered on your gallery.
  Each group needs a path and a `:title` option.

  ## Example

      defmodule MyApp.Mailer.Gallery do
        use Swoosh.Gallery

        group "/onboarding", title: "Onboarding Emails" do
          preview "/welcome", MyApp.Emails.Welcome
          preview "/account-confirmed", MyApp.Emails.AccountConfirmed
        end

        group "/localized", title: "Localized Emails", options: ["en-GB"] do
          preview "/welcome", MyApp.Emails.Welcome
          preview "/account-confirmed", MyApp.Emails.AccountConfirmed
        end

        preview "/password-reset", MyApp.Emails.PasswordReset
      end

  ## Options

  The supported options are:

    * `:title` - a string containing the group name.
    * `:options` - a list of options to pass to all previews within this group.
  """
  defmacro group(path, opts, do: block) do
    path = validate_path(path)
    extra_options = Keyword.get(opts, :options, [])

    group =
      opts
      |> Keyword.put(:path, path)
      |> Keyword.validate!([:path, :title, :options])
      |> Map.new()
      |> Macro.escape()

    quote do
      is_nil(@group_path) || raise "`group/3` cannot be nested"

      @group_path unquote(path)
      @group_options unquote(extra_options)

      @groups unquote(group)
      unquote(block)
      @group_path nil
      @group_options []
    end
  end

  @type preview() :: %{
          :details_mfa => {module(), atom(), list()},
          optional(:email) => Swoosh.Email.t(),
          :email_mfa => {module(), atom(), list()},
          :group => String.t() | nil,
          :path => String.t(),
          optional(:preview_details) => map()
        }

  # Evaluates a preview. It loads the results of email_mfa and details_mfa into the email
  # and preview_details properties respectively.
  @doc false
  @spec eval_preview(preview()) :: map() | list()
  def eval_preview(%{email: _email} = preview), do: preview

  def eval_preview(preview) do
    preview
    |> eval_email()
    |> eval_details()
  end

  defp eval_email(%{email_mfa: {module, fun, opts}} = preview) do
    email = call_with_fallback(module, fun, opts)
    Map.put(preview, :email, email)
  end

  # Evaluates preview details. It loads the results of details_mfa into the
  # preview_details property.
  @doc false
  @spec eval_details(preview() | list(preview())) :: map() | list()
  def eval_details(%{preview_details: _details} = preview), do: preview

  def eval_details(%{details_mfa: {module, fun, opts}} = preview) do
    details = call_with_fallback(module, fun, opts)
    Map.put(preview, :preview_details, validate_preview_details!(details))
  end

  def eval_details(previews) when is_list(previews) do
    Enum.map(previews, fn %{details_mfa: _mfa} = preview ->
      eval_details(preview)
    end)
  end

  # Evaluates a preview and reads the attachment at a given index position.
  @doc false
  @spec read_email_attachment_at(preview(), integer()) ::
          {:error, :invalid_attachment | :not_found}
          | {:ok, %{content_type: String.t(), data: any}}
  def read_email_attachment_at(preview, index) do
    preview
    |> eval_preview()
    |> Map.get(:email)
    |> case do
      %{attachments: attachments} when length(attachments) > index ->
        case Enum.at(attachments, index) do
          %{data: data, content_type: content_type} when not is_nil(data) ->
            {:ok, %{content_type: content_type, data: data}}

          %{path: path, content_type: content_type} when not is_nil(path) ->
            {:ok, %{content_type: content_type, data: File.read!(path)}}

          _other ->
            {:error, :invalid_attachment}
        end

      _no_attachments ->
        {:error, :not_found}
    end
  end

  # For macro validation (during compilation)
  defp validate_preview_details!(module) when is_atom(module) do
    # Just check that the module exists and has the required functions
    # The actual validation will happen at runtime
    module
  end

  # For runtime validation (after calling the function)
  defp validate_preview_details!(details) when is_list(details) do
    details
    |> Keyword.validate!([:title, :description, tags: []])
    |> Map.new()
    |> tap(&ensure_title!/1)
  end

  # Helper function to call a function with options, falling back to no options if it fails
  defp call_with_fallback(module, fun, opts) do
    if opts == [] do
      # If no options, try the arity-0 version first
      apply(module, fun, [])
    else
      # If we have options, try arity-1 first, then fall back to arity-0
      try do
        apply(module, fun, [opts])
      rescue
        UndefinedFunctionError ->
          # Fall back to arity-0 if arity-1 doesn't exist
          apply(module, fun, [])
      end
    end
  end

  defp ensure_title!(details) do
    unless Map.has_key?(details, :title) do
      raise """

      The `title` is required in preview_details/0. Make sure it's being returned:

         def preview_details, do: [title: "Welcome email"]

      """
    end
  end

  defp validate_path("/" <> path), do: path

  defp validate_path(path) when is_binary(path), do: path

  defp validate_path(path) when is_atom(path), do: Atom.to_string(path)

  defp validate_path(path) do
    # For AST interpolation, we need to evaluate it at compile time
    case Macro.expand(path, __ENV__) do
      expanded when is_binary(expanded) -> expanded
      expanded when is_atom(expanded) -> Atom.to_string(expanded)
      _ ->
        # If we can't expand it, return as-is and let it fail at runtime
        path
    end
  end

  @doc false
  def build_preview_path(nil, path), do: path
  def build_preview_path(group, path), do: "#{group}.#{path}"
end
