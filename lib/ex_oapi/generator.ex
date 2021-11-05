defmodule ExOAPI.Generator do
  alias ExOAPI.Parser.V3.Context

  require Logger

  @moduledoc """
  The ExOAPI SDK generator.

  This module is responsible for taking a %ExOAPI.Context{} and a keyword list of
  options and with those generate all needed modules while dumping them into files.
  """

  @templates_path "templates"

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
    :schemas_title,
    output_type: :modules,
    optional_args: :keyword,
    errors: [],
    calls: [],
    transforms_paths: nil,
    transforms_schemas: nil,
    transforms_context: nil
  ]

  def generate_app(%Context{} = ctx, opts) do
    with {_, {:ok, output_path}} <- {:output_path, Map.fetch(opts, :output_path)},
         {_, {:ok, title}} when is_binary(title) <- {:title, Map.fetch(opts, :title)},
         :ok <- File.mkdir_p(output_path) do
      try do
        case build_app_structure(output_path, title, ctx, opts) do
          {:ok, new_opts} ->
            generate_templates(ctx, new_opts)

          error ->
            error
        end
      rescue
        exception ->
          File.rm_rf!(output_path)
          reraise exception, __STACKTRACE__
      end
    else
      {:error, error} ->
        {:error, {"Unable to create app folder", error}}

      {what, _} ->
        {:error, "No option #{what} specified"}
    end
  end

  def build_app_structure(output_path, title, ctx, opts) do
    with priv <- :code.priv_dir(:ex_oapi),
         templates_path <- Path.join([priv, @templates_path, "app_mode"]),
         lib_path <- Path.join([output_path, "lib"]),
         sdk_path <- Path.join([lib_path, "sdk"]),
         :ok <- File.mkdir_p(sdk_path),
         sdk_title <- Enum.join([title, "SDK"], "."),
         schemas_title <- Enum.join([title, "Schemas"], "."),
         app_title <-
           String.split(title, ".")
           |> Enum.map(fn segment -> ExOAPI.EctoTypes.Underscore.cast!(segment) end)
           |> Enum.join("_")
           |> String.downcase(),
         mix_template <- Path.join([templates_path, "mix.eex"]),
         readme_template <- Path.join([templates_path, "README.eex"]),
         gitignore_template <- Path.join([templates_path, "gitignore.eex"]),
         main_template <- Path.join([templates_path, "main.eex"]),
         mix_final_path <- Path.join([output_path, "mix.exs"]),
         readme_final_path <- Path.join([output_path, "README.md"]),
         gitignore_final_path <- Path.join([output_path, ".gitignore"]),
         main_final_path <- Path.join([lib_path, "#{app_title}.ex"]) do
      description =
        case ctx.info.description do
          description when byte_size(description) > 1 ->
            description

          _ ->
            case ctx.info.title do
              info_title when byte_size(info_title) > 1 -> info_title
              _ -> "#{title} SDK Library for Elixir"
            end
        end

      create_file_from!(mix_template, mix_final_path,
        title: title,
        app_name: ":#{app_title}",
        app_version: "0.1.0",
        elixir_version: "~> 1.12",
        schemas_title: schemas_title,
        sdk_title: sdk_title,
        description: description
      )

      create_file_from!(main_template, main_final_path,
        title: title,
        ctx: ctx
      )

      create_file_from!(
        readme_template,
        readme_final_path,
        [
          title: title,
          sdk_title: sdk_title,
          schemas_title: schemas_title,
          app_name: ":#{app_title}",
          info: ctx.info
        ],
        no_format: true
      )

      create_file_from!(gitignore_template, gitignore_final_path, [app_name: "#{app_title}"],
        no_format: true
      )

      {:ok,
       opts
       |> Map.put(:output_path, sdk_path)
       |> Map.put(:title, sdk_title)
       |> Map.put(:schemas_title, schemas_title)}
    end
  end

  def generate_templates(%Context{} = ctx, opts) do
    Logger.info("Starting generation of the SDK")

    with {:ok, output_path} <- Map.fetch(opts, :output_path),
         :ok <- File.mkdir_p(output_path) do
      mod =
        %__MODULE__{ctx: ctx, output_path: output_path}
        |> add_base_paths()
        |> add_transforms(opts)
        |> add_opts(opts)
        |> maybe_transform_ctx()
        |> set_titles(opts)
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

  defp add_base_paths(%__MODULE__{} = mod) do
    priv_path = :code.priv_dir(:ex_oapi)

    %__MODULE__{
      mod
      | file_path_api: Path.join([priv_path, @templates_path, "base_module.eex"]),
        file_path_spec: Path.join([priv_path, @templates_path, "base_spec.eex"]),
        file_path_schema: Path.join([priv_path, @templates_path, "base_type.eex"])
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

  defp add_opts(%__MODULE__{} = mod, opts) do
    with optional_args <- Map.get(opts, :optional_args, :keyword) do
      %__MODULE__{
        mod
        | optional_args: optional_args
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

  defp set_titles(
         %__MODULE__{
           ctx: %Context{info: %{title: info_title}}
         } = mod,
         opts
       ) do
    opts_title = Map.get(opts, :title)
    title = if(opts_title, do: opts_title, else: info_title)

    title_split =
      title
      |> ExOAPI.Generator.Helpers.safe_mod_split()
      |> remove_invalid()
      |> filter_empty()

    title_mod = if(opts_title, do: opts_title, else: Enum.join(title_split, "."))
    file_path_title = Enum.join(title_split, "_") |> String.downcase()

    schemas_title =
      Map.get(
        opts,
        :schemas_title,
        ExOAPI.Generator.Helpers.schemas_title(title)
      )

    %__MODULE__{
      mod
      | title: title_mod,
        title_split: title_split,
        file_path_title: file_path_title,
        schemas_title: schemas_title
    }
  end

  defp generate_calls(%__MODULE__{transforms_paths: transform, ctx: ctx} = mod),
    do: %__MODULE__{mod | calls: assemble_calls(ctx, transform)}

  defp assemble_calls(%Context{paths: paths} = ctx, transform) do
    Enum.reduce(paths, %{}, fn {path, _}, acc ->
      generate_call(path, ctx, transform, acc)
    end)
  end

  defp generate_call(path, ctx, {m, f}, acc) do
    apply(m, f, [path, ctx])
    |> ExOAPI.Generator.Paths.new(ctx, acc)
  end

  defp generate_call(path, ctx, _, acc), do: ExOAPI.Generator.Paths.new(path, ctx, acc)

  defp dump_types(
         %__MODULE__{
           errors: [],
           output_path: output_path,
           file_path_schema: file_path_schema,
           schemas_title: title,
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
          title = title

          schema_title_split = ExOAPI.Generator.Helpers.safe_mod_split(s_title)

          schema_title = Enum.join([title | schema_title_split], ".")

          schema_title_path = Enum.join(schema_title_split, "_")

          dest_path_type =
            Path.join([output_path, "types", "#{Macro.underscore(schema_title_path)}.ex"])

          Logger.info("Dumping schema #{schema_title} into #{dest_path_type}")

          create_file_from!(file_path_schema, dest_path_type,
            ctx: ctx,
            title: title,
            schema_title: schema_title,
            schema_name: s_title,
            schema: schema,
            schemas: schemas
          )

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
           schemas_title: schemas_title,
           calls: all_calls,
           optional_args: optional_args,
           ctx: %Context{components: %{schemas: schemas} = components} = ctx
         } = mod
       ) do
    Enum.each(all_calls, fn {[module_title, module_path], calls} ->
      final_path =
        [file_path_title, module_path]
        |> filter_empty()
        |> Enum.join("_")

      dest_path_api = Path.join([output_path, "#{final_path}.ex"])

      final_title =
        [title, module_title]
        |> filter_empty()
        |> Enum.join(".")

      Logger.info("Starting dump of SDK module #{final_title} into #{dest_path_api}")

      create_file_from!(file_path_api, dest_path_api,
        ctx: ctx,
        title: title,
        final_title: final_title,
        schemas_title: schemas_title,
        calls: calls,
        components: components,
        schemas: schemas,
        optional_args: optional_args
      )
    end)

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
           schemas_title: schemas_title,
           ctx: ctx
         } = mod
       ) do
    :erlang.garbage_collect()
    dest_path_spec = Path.join([output_path, "#{file_path_title}_spec.ex"])

    Logger.info("Starting dump of ExOAPI.Spec module into #{dest_path_spec}")

    create_file_from!(file_path_spec, dest_path_spec,
      ctx: ctx,
      title: title,
      schemas_title: schemas_title
    )

    mod
  end

  defp dump_spec(mod), do: mod

  defp create_file_from!(file, dest, assigns, opts \\ []) do
    evaled = EEx.eval_file(file, assigns: assigns, file: file)

    :ok = File.mkdir_p(Path.dirname(dest))

    File.write!(dest, maybe_format_file(evaled, opts), [:raw])
  end

  defp maybe_format_file(file_content, opts) do
    case Keyword.get(opts, :no_format, false) do
      false -> Code.format_string!(file_content)
      _ -> file_content
    end
  end

  defp filter_empty(list) do
    list
    |> List.flatten()
    |> Enum.reject(fn el -> is_nil(el) or el == "" end)
  end

  defp remove_invalid(list) do
    list
    |> List.flatten()
    |> Enum.filter(fn el -> Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9]/, el) end)
  end
end
