defmodule ExOAPI.Parser.V3.Context.Schema.Map do
  @behaviour Ecto.Type

  import Ecto.Changeset, only: [apply_action: 2]

  alias ExOAPI.Parser.V3.Context

  @type t() :: %{String.t() => Context.Schema}

  @ex_oapi_schemas ExOAPI.Parser.ex_oapi_schemas()
  @ex_oapi_cull_schemas? ExOAPI.Parser.ex_oapi_cull_schemas()

  @impl Ecto.Type
  def type, do: :map

  @impl Ecto.Type
  def load(data), do: cast(data)

  @impl Ecto.Type
  def cast(data) when is_map(data) do
    schemas =
      case Process.get(@ex_oapi_cull_schemas?, false) do
        false -> nil
        _ -> Process.get(@ex_oapi_schemas)
      end

    Enum.reduce_while(data, {:ok, %{}}, fn {k, v}, {_, acc} ->
      v =
        v
        |> Map.put("title", k)
        |> Map.put("field_name", k)

      case is_nil(schemas) or is_map_key(schemas, k) do
        true ->
          with %Ecto.Changeset{} = changeset <- Context.Schema.map_cast(v, k),
               {:ok, applied} <- apply_action(changeset, :insert) do
            {:cont, {:ok, Map.put(acc, k, applied)}}
          else
            {:error, changeset} ->
              {:halt, {:error, {k, v, changeset}}}
          end

        _ ->
          Context.skipped_schema(k, v)
          {:cont, {:ok, acc}}
      end
    end)
    |> case do
      {:ok, _} = ok ->
        ok

      {:error, {k, v, changeset}} ->
        raise "Error casting Schema: #{inspect(k)} -> #{inspect(v)} resulting in #{inspect(changeset)}"
    end
  end

  def cast(_), do: :error

  @impl Ecto.Type
  def dump(data) when is_map(data), do: {:ok, data}
  def dump(nil), do: {:ok, %{}}
  def dump(_), do: :error

  @impl Ecto.Type
  def equal?(a, a), do: true
  def equal?(_, _), do: false

  @impl Ecto.Type
  def embed_as(_), do: :self
end
