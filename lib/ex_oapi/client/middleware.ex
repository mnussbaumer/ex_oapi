defmodule Tesla.Middleware.RequestResponse do
  alias ExOAPI.Parser.V3.Context
  alias Context.{Schema, Operation}

  @moduledoc """
  """

  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    env
    |> encode(opts)
    |> Tesla.run(next)
    |> case do
      {:ok, env} -> {:ok, decode(env, opts)}
      error -> error
    end
  end

  def encode(env, opts) do
    with ex_oapi_details <- Keyword.get(opts, :ex_oapi),
         {:ok, {body, content_type}} <- make_body_and_type(env, ex_oapi_details) do
      env
      |> Map.put(:body, body)
      |> Tesla.put_headers([{"content-type", content_type}])
    else
      # with multipart we let tesla handle the headers and content-type
      {:multipart, body} ->
        env
        |> Map.put(:body, body)

      :no_op ->
        env

      {:error, _} = error ->
        error
    end
  end

  def make_body_and_type(%{body: nil}, _), do: :no_op

  def make_body_and_type(_, %ExOAPI.Client{oapi_op: nil}),
    do: :no_op

  def make_body_and_type(
        %{body: body},
        %ExOAPI.Client{
          outgoing_format: outgoing_format,
          module: module,
          oapi_op: %Operation{
            servers: _servers,
            request_body: %Context.RequestBody{content: content}
          }
        }
      ) do
    case Map.get(content, outgoing_format) do
      %Context.Media{} = media -> {:ok, {outgoing_format, media}}
      nil when map_size(content) == 1 -> {:ok, hd(Map.to_list(content))}
      nil -> {:error, {:unexisting_media_format, outgoing_format}}
    end
    |> case do
      {:ok, {content_type, media}} ->
        encode_body(media, content_type, body, module)

      {:error, _} = error ->
        error
    end
  end

  def encode_body(_, content_type, body, _) when is_binary(body),
    do: {:ok, {body, content_type}}

  def encode_body(
        %Context.Media{
          schema: schema,
          encoding: encoding
        } = _media,
        content_type,
        body,
        module
      ) do
    spec_module = Module.concat(module, ExOAPI.Spec)
    %Context{} = spec = spec_module.spec()

    schema = get_schema(schema, spec)

    case encode_body_by_schema(schema, encoding, content_type, body, module) do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
      {:multipart, _} = multipart -> multipart
    end
  end

  def encode_body_by_schema(
        %Schema{},
        _encoding,
        "application/x-www-form-urlencoded" = content_type,
        body,
        _
      ),
      do: {:ok, {Plug.Conn.Query.encode(body), content_type}}

  def encode_body_by_schema(
        %Schema{},
        _encoding,
        "multipart/form-data",
        %Tesla.Multipart{} = body,
        _
      ),
      do: {:multipart, body}

  def encode_body_by_schema(
        %Schema{title: title},
        _encoding,
        "application/json" = content_type,
        body,
        module
      )
      when is_binary(title) do
    schema_module = Module.concat(module, title)

    if function_exported?(schema_module, :changeset, 2) do
      body
      |> schema_module.changeset()
      |> Ecto.Changeset.apply_action(:insert)
      |> case do
        {:ok, _} -> {:ok, {Jason.encode!(body), content_type}}
        {:error, changeset} -> {:error, changeset.errors}
      end
    else
      body
    end
  end

  @doc """
  Decode response body as querystring.

  It is used by `Tesla.Middleware.DecodeFormUrlencoded`.
  """
  def decode(env, opts) do
    env
    |> Map.update!(:body, &decode_body(&1, opts))
  end

  defp decode_body(body, opts), do: do_decode(body, opts)

  defp do_decode(data, _opts),
    do: Jason.decode!(data)

  defp get_schema(%Context.Schema{ref: nil} = schema, _), do: schema

  defp get_schema(%Context.Schema{ref: ref}, ctx),
    do: ExOAPI.Generator.Helpers.extract_ref(ref, ctx)
end
