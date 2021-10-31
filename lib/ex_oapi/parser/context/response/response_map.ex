defmodule ExOAPI.Parser.V3.Context.Response.Map do
  @behaviour Ecto.Type

  import Ecto.Changeset, only: [apply_action: 2]

  alias ExOAPI.Parser.V3.Context

  @type t() :: %{String.t() => Context.Response.t()}

  @impl Ecto.Type
  def type, do: :map

  @impl Ecto.Type
  def load(data), do: cast(data)

  @impl Ecto.Type
  def cast(data) when is_map(data) do
    Enum.reduce_while(data, {:ok, %{}}, fn {k, v}, {_, acc} ->
      with changeset <- Context.Response.map_cast(v),
           {:ok, applied} <- apply_action(changeset, :insert) do
        {:cont, {:ok, Map.put(acc, k, applied)}}
      else
        {:error, changeset} ->
          {:halt, {:error, {k, v, changeset}}}
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
