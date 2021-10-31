defmodule ExOAPI.Client.Responses do
  alias ExOAPI.Parser.V3.Context
  alias Context.{Schema, Media}
  alias ExOAPI.Generator.Helpers

  def convert_response(body, %Media{schema: schema}, spec, module),
    do: do_conversion(body, schema, spec, module)

  def convert_response(body, _, _spec, _module),
    do: {:ok, body}

  def do_conversion(
        value,
        %Schema{type: "object", ref: nil, properties: properties},
        spec,
        module
      )
      when is_map(value) and is_map(properties) do
    Enum.reduce(value, value, fn {k, v}, acc ->
      prop = Map.get(properties, k)
      Map.put(acc, k, do_conversion(v, prop, spec, module))
    end)
  end

  def do_conversion(
        value,
        %Schema{type: "array", ref: nil, items: item},
        spec,
        module
      )
      when is_list(value) and not is_nil(item) do
    Enum.map(value, fn value_item -> do_conversion(value_item, item, spec, module) end)
  end

  def do_conversion(value, %Schema{ref: ref}, spec, module) when not is_nil(ref) do
    with %Context.Schema{title: title} <- Helpers.extract_ref(ref, spec),
         schema_module <- Module.concat(module, title),
         {:module, _} <- Code.ensure_loaded(schema_module),
         true <- function_exported?(schema_module, :changeset, 2) do
      value
      |> schema_module.changeset()
      |> Ecto.Changeset.apply_action(:insert)
      |> case do
        {:ok, converted} ->
          converted

        {:error, _changeset} ->
          value
      end
    else
      _what -> value
    end
  end

  def do_conversion(value, _, _, _), do: value
end
