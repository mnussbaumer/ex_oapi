defmodule ExOAPI.Generator do
  alias ExOAPI.Parser.V3.Context

  require Logger

  @moduledoc """
  The ExOAPI SDK generator.

  This module is responsible for taking a %ExOAPI.Context{} and a keyword list of
  options and with those generate all needed modules while dumping them into files.
  """

  @enforce_keys [:ctx]
  defstruct [
    :ctx,
    :file_path_api,
    :file_path_spec,
    :file_path_schema,
    :title,
    :title_split,
    :file_path_title,
    :output_path,
    output_type: :modules,
    errors: [],
    calls: [],
    transforms_paths: nil,
    transforms_schemas: nil,
    transforms_context: nil,
    base_templates_path: "templates"
  ]

  def generate_templates(%Context{} = ctx, opts) do
    Logger.info("Starting generation of the SDK")

    with {:ok, output_path} <- Map.fetch(opts, :output_path),
         :ok <- File.mkdir_p(output_path) do
      mod =
        %__MODULE__{ctx: ctx, output_path: output_path}
        |> add_base_paths()
        |> add_transforms(opts)
        |> maybe_transform_ctx()
        |> set_title(opts)
        |> generate_calls()

      try do
        mod
        |> dump_types()
        |> dump_api()
        |> dump_spec()
        |> case do
          %__MODULE__{errors: []} ->
            :ok

          %__MODULE__{errors: errors} ->
            File.rm_rf!(mod.output_path)
            {:error, errors}
        end
      rescue
        exception ->
          File.rm_rf!(mod.output_path)
          reraise exception, __STACKTRACE__
      end
    else
      error -> {:error, {:generating_output_path, error}}
    end
  end

  defp add_base_paths(%__MODULE__{base_templates_path: btp} = mod) do
    priv_path = :code.priv_dir(:ex_oapi)

    %__MODULE__{
      mod
      | file_path_api: Path.join([priv_path, btp, "base_module.eex"]),
        file_path_spec: Path.join([priv_path, btp, "base_spec.eex"]),
        file_path_schema: Path.join([priv_path, btp, "base_type.eex"])
    }
  end

  defp add_transforms(%__MODULE__{} = mod, opts) do
    with paths_transforms <- Map.get(opts, :paths_transforms, nil),
         schemas_transforms <- Map.get(opts, :schemas_transforms, nil),
         context_transforms <- Map.get(opts, :context_transforms, nil) do
      %__MODULE__{
        mod
        | transforms_paths: paths_transforms,
          transforms_schemas: schemas_transforms,
          transforms_context: context_transforms
      }
    end
  end

  defp maybe_transform_ctx(%__MODULE__{ctx: ctx, transforms_context: transform} = mod) do
    case transform do
      {m, f} ->
        Logger.info("Trying transform on the ExOAPI.Parser context before generation")

        case apply(m, f, [ctx]) do
          {:ok, new_ctx} -> %__MODULE__{mod | ctx: new_ctx}
          {:error, error} -> %__MODULE__{mod | errors: [error | mod.errors]}
        end

      _ ->
        mod
    end
  end

  defp set_title(
         %__MODULE__{
           output_path: bop,
           ctx: %Context{info: %{title: info_title}}
         } = mod,
         opts
       ) do
    title = Map.get(opts, :title, info_title)
    title_split = ExOAPI.Generator.Helpers.safe_mod_split(title)
    title_mod = Enum.join(title_split, ".")
    file_path_title = Enum.join(title_split, "_") |> String.downcase()

    %__MODULE__{
      mod
      | title: title_mod,
        title_split: title_split,
        file_path_title: file_path_title,
        output_path: Path.join([bop, file_path_title])
    }
  end

  defp generate_calls(%__MODULE__{transforms_paths: transform, ctx: ctx} = mod),
    do: %__MODULE__{mod | calls: assemble_calls(ctx, transform)}

  defp assemble_calls(%Context{paths: paths} = ctx, transform) do
    Enum.reduce(paths, [], fn {path, _}, acc ->
      [generate_call(path, ctx, transform) | acc]
    end)
    |> List.flatten()
    |> Enum.reverse()
  end

  defp generate_call(path, ctx, {m, f}) do
    apply(m, f, [path, ctx])
    |> ExOAPI.Generator.Paths.new(ctx)
  end

  defp generate_call(path, ctx, _), do: ExOAPI.Generator.Paths.new(path, ctx)

  defp dump_types(
         %__MODULE__{
           errors: [],
           output_path: output_path,
           file_path_schema: file_path_schema,
           title: title,
           ctx: %Context{components: %{schemas: schemas}} = ctx
         } = mod
       ) do
    Logger.info("Starting dump of schemas into Ecto embeds")

    Enum.each(
      schemas,
      fn
        {_, %{properties: nil}} ->
          :ok

        {s_title, schema} ->
          schema_title_split = ExOAPI.Generator.Helpers.safe_mod_split(s_title)
          schema_title = Enum.join([title | schema_title_split], ".")
          schema_title_path = Enum.join(schema_title_split, "_")
          dest_path_type = Path.join([output_path, "types", "#{schema_title_path}.ex"])

          Logger.info("Dumping schema #{schema_title} into #{dest_path_type}")

          evaled =
            EEx.eval_file(file_path_schema,
              assigns: [
                ctx: ctx,
                title: title,
                schema_title: schema_title,
                schema_name: s_title,
                schema: schema,
                schemas: schemas
              ],
              file: file_path_schema
            )

          :ok = File.mkdir_p(Path.dirname(dest_path_type))

          File.write!(dest_path_type, Code.format_string!(evaled), [:raw])
          :erlang.garbage_collect()
      end
    )

    mod
  end

  defp dump_types(mod), do: mod

  defp dump_api(
         %__MODULE__{
           errors: [],
           output_path: output_path,
           file_path_title: file_path_title,
           file_path_api: file_path_api,
           title: title,
           calls: calls,
           ctx: %Context{components: %{schemas: schemas} = components} = ctx
         } = mod
       ) do
    dest_path_api = Path.join([output_path, "#{file_path_title}.ex"])

    Logger.info("Starting dump of SDK module #{title} into #{file_path_title}")

    evaled =
      EEx.eval_file(file_path_api,
        assigns: [
          ctx: ctx,
          title: title,
          calls: calls,
          components: components,
          schemas: schemas
        ],
        file: file_path_api
      )

    :ok = File.mkdir_p(Path.dirname(dest_path_api))
    File.write!(dest_path_api, Code.format_string!(evaled), [:raw])
    mod
  end

  defp dump_api(mod), do: mod

  defp dump_spec(
         %__MODULE__{
           errors: [],
           output_path: output_path,
           file_path_title: file_path_title,
           file_path_spec: file_path_spec,
           title: title,
           ctx: ctx
         } = mod
       ) do
    :erlang.garbage_collect()
    dest_path_spec = Path.join([output_path, "#{file_path_title}_spec.ex"])

    Logger.info("Starting dump of ExOAPI.Spec module into #{dest_path_spec}")

    evaled =
      EEx.eval_file(file_path_spec,
        assigns: [
          ctx: ctx,
          title: title
        ],
        file: file_path_spec
      )

    :ok = File.mkdir_p(Path.dirname(dest_path_spec))
    File.write!(dest_path_spec, Code.format_string!(evaled), [:raw])
    mod
  end

  defp dump_spec(mod), do: mod
end
