defmodule ExOAPI.Client.Responses do
  alias ExOAPI.Parser.V3.Context
  alias Context.{Schema, Media}
  alias ExOAPI.Generator.Helpers

  def convert_response(body, %Media{schema: schema}, spec, spec_module, strict),
    do: {:ok, do_conversion(body, schema, spec, spec_module, strict)}

  def convert_response(body, _, _spec, _spec_module, _strict),
    do: {:ok, body}

  def do_conversion(
        value,
        %Schema{type: :object, ref: nil, properties: properties},
        spec,
        spec_module,
        strict
      )
      when is_map(value) and is_map(properties) do
    Enum.reduce(value, value, fn {k, v}, acc ->
      prop = Map.get(properties, k)
      Map.put(acc, k, do_conversion(v, prop, spec, spec_module, strict))
    end)
  end

  def do_conversion(
        value,
        %Schema{type: :array, ref: nil, items: item},
        spec,
        spec_module,
        strict
      )
      when is_list(value) and not is_nil(item) do
    Enum.map(value, fn value_item ->
      do_conversion(value_item, item, spec, spec_module, strict)
    end)
  end

  def do_conversion(value, %Schema{ref: ref}, spec, spec_module, strict) when not is_nil(ref) do
    with %Context.Schema{title: title} <- Helpers.extract_ref(ref, spec),
         camelized <- Helpers.safe_mod_split(title),
         schema_module <- Module.concat([spec_module.schemas_title() | camelized]),
         {:module, _} <- Code.ensure_loaded(schema_module),
         true <- function_exported?(schema_module, :changeset, 2),
         changeset <- schema_module.changeset(value) do
      case strict do
        true -> Ecto.Changeset.apply_action(changeset, :insert)
        _ -> {:changed, Ecto.Changeset.apply_changes(changeset)}
      end
      |> case do
        {:ok, converted} ->
          converted

        {:changed, converted} ->
          converted

        {:error, _changeset} ->
          value
      end
    else
      _what ->
        value
    end
  end

  def do_conversion(value, _, _, _, _), do: value
end
