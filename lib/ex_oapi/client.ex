defmodule ExOAPI.Client do
  alias ExOAPI.Parser.V3.Context
  alias Context.Operation

  @moduledoc """
  The client module used to provide an api for generating requests programatically
  inside the generated SDK functions.
  """

  defstruct [
    :method,
    :base_url,
    :path,
    :body,
    :adapter,
    :module,
    opts: [],
    query: [],
    headers: [],
    replacements: [],
    errors: [],
    outgoing_format: "application/json",
    response_handler: &__MODULE__.response_handler/2,
    middleware: [
      {Tesla.Middleware.FollowRedirects, max_redirects: 5},
      {Tesla.Middleware.Timeout, timeout: 5_000}
    ]
  ]

  @type t() :: %__MODULE__{
          method: nil | ExOAPI.EctoTypes.HTTPMethods.t(),
          base_url: nil | String.t(),
          path: nil | String.t(),
          body: any(),
          adapter: {any(), Keyword.t()},
          module: module() | nil,
          opts: Keyword.t(),
          query: Keyword.t(),
          headers: list({String.t(), String.t()}),
          replacements: list({String.t(), String.t()}),
          errors: list(any()),
          outgoing_format: String.t(),
          response_handler: function() | mfa(),
          middleware: middleware()
        }

  def request(%ExOAPI.Client{errors: [_ | _] = errors}), do: {:error, errors}

  def request(
        %ExOAPI.Client{
          method: method,
          opts: opts,
          query: query,
          headers: headers,
          body: body,
          base_url: base_url,
          path: path,
          replacements: replacements,
          response_handler: response_handler,
          middleware: middleware,
          adapter: adapter
        } = client
      ) do
    url = replace_path_fragments(replacements, "#{base_url}#{path}")

    case adapter do
      nil -> Tesla.client(middleware)
      _ -> Tesla.client(middleware, adapter)
    end
    |> Tesla.request(
      url: url,
      method: method,
      body: body,
      query: query,
      headers: headers,
      opts: opts
    )
    |> response_handler(client, response_handler)
  end

  def response_handler(response, client, nil), do: response_handler(response, client)

  def response_handler(response, client, fun) when is_function(fun),
    do: fun.(response, client)

  def response_handler(response, client, {m, f, a}),
    do: apply(m, f, [response, client | a])

  def response_handler(response, _client, {m, f}),
    do: apply(m, f, [response])

  def response_handler(
        {:ok, %Tesla.Env{body: body, status: status}},
        %{path: path, module: module, method: method, outgoing_format: format} = _client
      ) do
    with spec_module <- Module.concat(module, ExOAPI.Spec),
         {_, %Context{} = spec} <- {:spec, spec_module.spec()},
         {_, %Context.Paths{} = path_def} <- {:path, Map.get(spec.paths, path)},
         {_, %Operation{responses: resp_spec}} <- {:req, Map.get(path_def, method)} do
      maybe_convert_response("#{status}", body, resp_spec, spec, format, module)
    else
      _ -> {:ok, body}
    end
  end

  def response_handler(response, _client), do: response

  defp maybe_convert_response(status, body, resp_spec, spec, format, module)
       when is_map_key(resp_spec, status) or is_map_key(resp_spec, "default") do
    Map.get(resp_spec, status, Map.get(resp_spec, "default"))
    |> case do
      %Context.Response{content: format_spec} when is_map_key(format_spec, format) ->
        __MODULE__.Responses.convert_response(body, Map.get(format_spec, format), spec, module)

      _ ->
        {:ok, body}
    end
  end

  defp maybe_convert_response(_, body, _, _, _, _), do: {:ok, body}

  @path_regex ~r/\((?<regex_start>.+)\{(?<replacement>.+)\}(?<regex_end>.+)\)(\/|$)|\{(?<only_interpolation>.+)\}(\/|$)/u
  def replace_path_fragments(replacements, url) do
    Regex.scan(@path_regex, url)
    |> Enum.reduce(url, fn
      [_, "", "", "", "", key, _], acc ->
        String.replace(acc, "{#{key}}", Map.fetch!(replacements, key))

      [special, _regex_type, key, _regex_spec, delimiter], acc ->
        String.replace(acc, special, Map.fetch!(replacements, key) <> delimiter)
    end)
  end

  @doc """
  Adds options to be passed to the tesla adapter.
  """
  @spec add_options(__MODULE__.t(), Keyword.t() | {atom(), any()}) :: __MODULE__.t()
  def add_options(client, opts) when is_list(opts),
    do: %{client | opts: Enum.concat(client.opts, opts)}

  def add_options(client, {_, _} = opt),
    do: %{client | opts: Enum.concat(client.opts, [opt])}

  @type middleware :: {any(), any()}

  @doc """
  Adds middleware to the client that will be passed on to the Tesla request.
  """
  @spec add_middleware(__MODULE__.t(), list(middleware()) | middleware() | module()) ::
          __MODULE__.t()
  def add_middleware(client, middleware) when is_list(middleware),
    do: %{client | middleware: Enum.concat(client.middleware, middleware)}

  def add_middleware(client, {_, _} = middleware),
    do: %{client | middleware: Enum.concat(client.middleware, [middleware])}

  def add_middleware(client, middleware),
    do: %{client | middleware: Enum.concat(client.middleware, [middleware])}

  @doc """
  Sets the adapter options that will be passed on to the Tesla request.
  """
  @spec set_adapter(__MODULE__.t(), {any(), Keyword.t()}) :: __MODULE__.t()
  def set_adapter(client, {_, _} = adapter),
    do: %{client | adapter: adapter}

  @doc false
  @spec set_module(__MODULE__.t(), module()) :: __MODULE__.t()
  def set_module(client, module) when is_atom(module),
    do: %{client | module: module}

  @doc false
  @spec add_method(__MODULE__.t(), ExOAPI.EctoTypes.HTTPMethods.t()) :: __MODULE__.t()
  def add_method(client, method), do: %{client | method: method}

  @doc """
  Sets the `:base_url` to be used as the API endpoint.
  """
  @spec add_base_url(__MODULE__.t(), String.t()) :: __MODULE__.t()
  @spec add_base_url(__MODULE__.t(), String.t(), nil | :exoapi_default) :: __MODULE__.t()
  def add_base_url(client, url),
    do: add_base_url(client, url, nil)

  def add_base_url(%__MODULE__{base_url: b_url} = client, _url, :exoapi_default)
      when not is_nil(b_url),
      do: client

  def add_base_url(%__MODULE__{} = client, url, _type), do: %{client | base_url: url}

  @doc false
  @spec add_path(__MODULE__.t(), String.t()) :: __MODULE__.t()
  def add_path(%__MODULE__{} = client, path), do: %{client | path: path}

  @doc false
  @spec add_body(__MODULE__.t(), String.t() | map()) :: __MODULE__.t()
  def add_body(%{path: path, module: module, method: method} = client, body) do
    with spec_module <- Module.concat(module, ExOAPI.Spec),
         {_, %Context{} = spec} <- {:spec, spec_module.spec()},
         {_, %Context.Paths{} = path_def} <- {:path, Map.get(spec.paths, path)},
         {_, %Operation{request_body: req}} <- {:req, Map.get(path_def, method)} do
      validate_request_body(client, body, spec, req)
    else
      {_, _} -> %{client | body: body}
    end
  end

  defp validate_request_body(%{outgoing_format: format} = client, body, spec, req) do
    case (req.required && body && true) || not req.required do
      false ->
        add_client_error(client, :missing_required_body)

      true ->
        with content <- Map.get(req, :content, %{}),
             {_, %Context.Media{schema: schema}} <- {:outgoing, Map.get(content, format)},
             {_, %Context.Schema{} = schema} <- {:schema, get_schema(schema, spec)},
             {_, true} <- {:valid?, validate_schema(client, body, schema, req.required)} do
          %{client | body: body}
        else
          {:valid?, {:error, errors}} -> add_client_error(client, errors)
          {_, _} -> %{client | body: body}
        end
    end
  end

  defp get_schema(%Context.Schema{ref: nil} = schema, _), do: schema

  defp get_schema(%Context.Schema{ref: ref}, ctx),
    do: ExOAPI.Generator.Helpers.extract_ref(ref, ctx)

  defp validate_schema(_, body, _, false), do: body

  defp validate_schema(
         %{outgoing_format: "application/json", module: module} = _client,
         %{} = body,
         %{title: title} = _schema,
         true
       ) do
    schema_module = Module.concat(module, title)

    if function_exported?(schema_module, :changeset, 2) do
      body
      |> schema_module.changeset()
      |> Ecto.Changeset.apply_action(:insert)
      |> case do
        {:ok, _} -> true
        {:error, changeset} -> {:error, changeset.errors}
      end
    else
      body
    end
  end

  defp validate_schema(_, body, _, _), do: body

  defp add_client_error(%{errors: errors} = client, new_errors) when is_list(new_errors) do
    %{client | errors: Enum.concat(errors, new_errors)}
  end

  defp add_client_error(%{errors: errors} = client, new_error) do
    %{client | errors: Enum.concat(errors, [new_error])}
  end

  @doc """
  Adds an header to the client.
  """
  @spec add_header(__MODULE__.t(), String.t(), String.t() | nil) :: __MODULE__.t()
  def add_header(client, _header, nil), do: client

  def add_header(%__MODULE__{headers: headers} = client, header, value) do
    %{client | headers: [{header, value} | headers]}
  end

  @doc """
  Adds a query param to the client.
  """
  @spec add_query(__MODULE__.t(), String.t() | atom(), String.t() | nil) ::
          __MODULE__.t()
  def add_query(client, _param, nil), do: client

  def add_query(%__MODULE__{query: query} = client, param, value) do
    %{client | query: [{param, value} | query]}
  end

  @doc false
  @spec replace_in_path(__MODULE__.t(), String.t(), String.t()) :: __MODULE__.t()
  def replace_in_path(%__MODULE__{replacements: replacements} = client, param, value) do
    %{client | replacements: [{param, value} | replacements]}
  end
end
