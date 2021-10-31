defmodule ExOAPI.EctoTypes.SecurityEntry do
  @behaviour Ecto.Type

  @type t() :: %{String.t() => list(String.t())}

  @impl Ecto.Type
  def type, do: :map

  @impl Ecto.Type
  def load(data), do: cast(data)

  @impl Ecto.Type
  def cast(data) when is_map(data), do: {:ok, data}
  def cast(nil), do: {:ok, %{}}
  def cast(_), do: :error

  @impl Ecto.Type
  def dump(data) when is_map(data), do: {:ok, data}
  def dump(nil), do: {:ok, %{}}
  def dump(_), do: :error

  @impl Ecto.Type
  def equal?(a, a), do: true
  def equal?(_, _), do: false

  @impl Ecto.Type
  def embed_as(_), do: :dump
end
