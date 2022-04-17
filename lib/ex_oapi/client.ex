defmodule ExOAPI.Client do
  alias ExOAPI.Parser.V3.Context
  alias Context.Operation

  @moduledoc """
  The client module used to provide an api for generating requests programatically
  inside the generated SDK functions.
  """

  @parsable_response_type ["application/json", "text/json", "*/*"]

  defstruct [
    :method,
    :base_url,
    :path,
    :body,
    :adapter,
    :module,
    :oapi_op,
    opts: [],
    query: [],
    headers: [],
    replacements: [],
    errors: [],
    strict_responses: false,
    outgoing_format: "application/json",
    response_handler: &__MODULE__.response_handler/2,
    middleware: [
      {Tesla.Middleware.FollowRedirects, max_redirects: 5},
      {Tesla.Middleware.Timeout, timeout: 15_000}
    ]
  ]

  @type t() :: %__MODULE__{
          method: nil | ExOAPI.EctoTypes.HTTPMethods.t(),
          base_url: nil | String.t(),
          path: nil | String.t(),
          body: any(),
          adapter: {any(), Keyword.t()},
          module: module() | nil,
          oapi_op: Context.Operation.t(),
          opts: Keyword.t(),
          query: Keyword.t(),
          headers: list({String.t(), String.t()}),
          replacements: list({String.t(), String.t()}),
          errors: list(any()),
          strict_responses: boolean(),
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
          path: path,
          replacements: replacements,
          response_handler: response_handler,
          middleware: middleware,
          adapter: adapter
        } = client
      ) do
    client = add_op_details(client)
    base_url = maybe_create_url_from_servers(client)
    url = replace_path_fragments(replacements, "#{base_url}#{path}")
    middleware = [{Tesla.Middleware.RequestResponse, ex_oapi: client} | middleware]

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
      opts: Keyword.put(opts, :ex_oapi, client)
    )
    |> response_handler(client, response_handler)
  end

  def maybe_create_url_from_servers(%ExOAPI.Client{
        base_url: base_url,
        oapi_op: %Operation{servers: [%Context.Server{url: server_url} | _] = servers}
      })
      when is_binary(server_url) do
    case check_url_in_servers(base_url, servers) do
      true ->
        base_url

      false ->
        server_url
    end
  end

  def maybe_create_url_from_servers(%ExOAPI.Client{base_url: base_url}),
    do: base_url

  def check_url_in_servers(base_url, servers),
    do: Enum.any?(servers, &(&1.url == base_url))

  def response_handler(response, client, nil), do: response_handler(response, client)

  def response_handler(response, client, fun) when is_function(fun),
    do: fun.(response, client)

  def response_handler(response, client, {m, f, a}),
    do: apply(m, f, [response, client | a])

  def response_handler(response, _client, {m, f}),
    do: apply(m, f, [response])

  def response_handler(
        {:ok, %Tesla.Env{body: body, status: status}},
        %{oapi_op: op, module: module, strict_responses: strict} = _client
      ) do
    with spec_module <- Module.concat(module, ExOAPI.Spec),
         {_, %Context{} = spec} <- {:spec, spec_module.spec()},
         {_, %Operation{responses: resp_spec}} <- {:req, op} do
      maybe_convert_response("#{status}", body, resp_spec, spec, spec_module, strict)
    else
      _ -> {:ok, body}
    end
  end

  def response_handler(response, _client), do: response

  defp maybe_convert_response(status, body, resp_spec, spec, module, strict)
       when is_map_key(resp_spec, status) or is_map_key(resp_spec, "default") do
    Map.get(resp_spec, status, Map.get(resp_spec, "default"))
    |> case do
      %Context.Response{content: format_spec} ->
        Enum.reduce_while(@parsable_response_type, {:ok, body}, fn format, acc ->
          case Map.get(format_spec, format) do
            nil ->
              {:cont, acc}

            resp_spec ->
              {:halt,
               __MODULE__.Responses.convert_response(body, resp_spec, spec, module, strict)}
          end
        end)

      _error ->
        {:ok, body}
    end
  end

  defp maybe_convert_response(_, body, _, _, _, _), do: {:ok, body}

  @path_regex ~r/\((?<regex_start>.+?)(?<replacement>\{.+?\})(?<regex_end>.+?)\)(?:\/|$)|(?<only_interpolation>\{.+?\})(?:\/|$)/u
  def replace_path_fragments(replacements, url) do
    Regex.scan(@path_regex, url)
    |> Enum.reduce(url, fn
      [_, "", "", "", key], acc ->
        {_, value} = Enum.find(replacements, fn {k, _v} -> "{#{k}}" == key end)
        String.replace(acc, key, value)

      [special, _regex_type, key, _regex_spec], acc ->
        {_, value} = Enum.find(replacements, fn {k, _v} -> "{#{k}}" == key end)
        String.replace(acc, special, value)
    end)
  end

  def add_arg_opts(client, type, in_type, opts, args) do
    Enum.reduce(args, client, fn {opt, name, style, explode}, acc ->
      value = get_arg_value(type, opts, opt)

      case build_arg_value(name, value, style, explode, in_type) do
        {:normal, prepared_value} ->
          add_arg_to_client(acc, type, name, prepared_value)

        {:explode, prepared_value} ->
          Enum.reduce(prepared_value, acc, fn {k, v}, acc_1 ->
            add_arg_to_client(acc_1, type, k, v)
          end)

        _ ->
          acc
      end
    end)
  end

  defp get_arg_value(:keyword, opts, opt), do: Keyword.get(opts, opt)
  defp get_arg_value(:map, opts, opt), do: Map.get(opts, opt)

  defp build_arg_value(name, value, style, false, in_type) when is_list(value) do
    case style do
      :matrix ->
        {:normal, ";#{name}=#{Enum.join(value, ",")}"}

      _ when style in [:form, :simple] and in_type == :query ->
        {:normal, "#{Enum.join(value, ",")}"}

      _ when style in [:form, :simple] ->
        {:normal, "#{name}=#{Enum.join(value, ",")}"}

      :label ->
        {:normal, ".#{Enum.join(value, ".")}"}

      _ ->
        {:normal, value}
    end
  end

  defp build_arg_value(name, value, style, true, in_type) when is_list(value) do
    case style do
      :matrix ->
        {
          :normal,
          Enum.map(value, fn v -> ";#{name}=#{v}" end) |> Enum.join()
        }

      _ when style in [:form, :simple] and in_type == :query ->
        {:normal, value}

      :form ->
        {:normal, "#{name}=#{Enum.join(value, ",")}"}

      :simple ->
        {:normal, Enum.join(value, ",")}

      :label ->
        {:normal, ".#{Enum.join(value, ".")}"}

      :spaceDelimited ->
        {:normal, "#{Enum.join(value, "%20")}"}

      :pipeDelimited ->
        {:normal, "#{Enum.join(value, "|")}"}

      _ ->
        {:normal, value}
    end
  end

  defp build_arg_value(name, value, style, false, in_type) when is_map(value) do
    case style do
      :matrix ->
        {:normal,
         ";#{name}=" <>
           (Enum.reduce(value, [], fn {k, v}, acc -> [v, k | acc] end)
            |> Enum.reverse()
            |> Enum.join(","))}

      _ when style in [:form, :simple] and in_type == :query ->
        {:normal,
         Enum.reduce(value, [], fn {k, v}, acc -> [v, k | acc] end)
         |> Enum.reverse()
         |> Enum.join(",")}

      :form ->
        {:normal,
         "#{name}=" <>
           (Enum.reduce(value, [], fn {k, v}, acc -> [v, k | acc] end)
            |> Enum.reverse()
            |> Enum.join(","))}

      :simple ->
        {:normal,
         Enum.reduce(value, [], fn {k, v}, acc -> [v, k | acc] end)
         |> Enum.reverse()
         |> Enum.join(",")}

      :label ->
        {:normal,
         Enum.reduce(value, ["."], fn {k, v}, acc -> [v, k | acc] end)
         |> Enum.reverse()
         |> Enum.join(".")}

      value ->
        {:normal, value}
    end
  end

  defp build_arg_value(name, value, style, true, in_type) when is_map(value) do
    case style do
      :matrix ->
        {:normal,
         ";" <>
           (Enum.reduce(value, [], fn {k, v}, acc -> [v, "#{k}=" | acc] end)
            |> Enum.reverse()
            |> Enum.join(";"))}

      :form when in_type == :query ->
        {:explode, value}

      :form ->
        {:normal,
         Enum.reduce(value, [], fn {k, v}, acc -> [v, "#{k}=" | acc] end)
         |> Enum.reverse()
         |> Enum.join("&")}

      :simple ->
        {:normal,
         Enum.reduce(value, [], fn {k, v}, acc -> [v, "#{k}=" | acc] end)
         |> Enum.reverse()
         |> Enum.join(",")}

      :label ->
        {:normal,
         "." <>
           (Enum.map(value, fn {k, v} -> "#{k}=#{v}" end)
            |> Enum.join("."))}

      :spaceDelimited ->
        {
          :normal,
          Enum.map(value, fn {k, v} -> "#{k}%20#{v}" end)
          |> Enum.join("%20")
        }

      :pipeDelimited ->
        {
          :normal,
          Enum.map(value, fn {k, v} -> "#{k}|#{v}" end)
          |> Enum.join("|")
        }

      :deepObject ->
        {:explode, Enum.map(value, fn {k, v} -> {"#{name}[#{k}]", v} end)}

      value ->
        value
    end
  end

  defp build_arg_value(_name, value, _style, _explode, _in_type), do: value

  def add_arg_to_client(client, type, name, prepared_value) do
    case type do
      :header -> add_header(client, name, prepared_value)
      :query -> add_query(client, name, prepared_value)
      :path -> replace_in_path(client, name, prepared_value)
    end
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
  def add_body(%__MODULE__{} = client, body),
    do: %{client | body: body}

  defp add_op_details(%{path: path, module: module, method: method} = client) do
    with spec_module <- Module.concat(module, ExOAPI.Spec),
         {_, %Context{} = spec} <- {:spec, spec_module.spec()},
         {_, %Context.Paths{} = path_def} <- {:path, Map.get(spec.paths, path)},
         {_, %Operation{} = op} <- {:req, Map.get(path_def, method)} do
      %{client | oapi_op: op}
    else
      {_, _} -> client
    end
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
