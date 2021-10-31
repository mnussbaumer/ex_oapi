defmodule ExOAPI do
  @moduledoc """
  The module containing the high-level functionality for generating SDKs from an
  OpenAPI V3 specification.
  """

  @spec generate(%{
          required(:source) => String.t(),
          required(:output_path) => String.t(),
          optional(:output_type) => :app | :modules,
          optional(:parser) => any(),
          optional(:generator) => any()
        }) :: {:ok, :generated} | {:error, term()}
  def generate(opts) do
    with source <- Map.get(opts, :source),
         {_, {:ok, output}} <- {:output, Map.fetch(opts, :output_path)},
         output_type <- Map.get(opts, :output_type, :modules),
         parse_config <- Map.get(opts, :parser, %{}),
         gen_config <- Map.get(opts, :generator, %{}),
         gen_config <- Map.put(gen_config, :output_type, output_type),
         gen_config <- Map.put(gen_config, :output_path, output),
         {_, :ok} <- {:source, verify_file(source)} do
      parse_and_create(source, parse_config, gen_config)
    else
      {:source, error} -> error
      {:output, _} -> {:error, :output_not_specified}
    end
  end

  defp parse_and_create(source, parse_config, gen_config) do
    with {:ok, ctx} <- parse(source, parse_config),
         {:ok, _} <- create(ctx, gen_config) do
      {:ok, :generated}
    end
  end

  defp parse(source, config) do
    with {_, {:ok, file}} <- {:read_source, File.read(source)},
         {_, {:ok, parsed}} <- {:json_parse, Jason.decode(file)} do
      config
      |> ExOAPI.Parser.V3.Context.new()
      |> ExOAPI.Parser.V3.Context.map_cast(parsed)
      |> ExOAPI.Parser.V3.Context.maybe_add_skipped_schemas()
    end
  end

  defp create(%ExOAPI.Parser.V3.Context{} = ctx, config),
    do: ExOAPI.Generator.generate_templates(ctx, config)

  defp verify_file(file_path) do
    with {_, true} <- {:exists?, File.exists?(file_path)},
         {_, false} <- {:dir?, File.dir?(file_path)} do
      :ok
    else
      {:exists?, _} -> {:error, {file_path, :enoent}}
      {:dir?, _} -> {:error, {file_path, :eisdir}}
    end
  end
end
