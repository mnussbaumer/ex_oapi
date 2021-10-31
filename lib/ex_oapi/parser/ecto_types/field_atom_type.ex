defmodule ExOAPI.EctoTypes.FieldAtom do
  @behaviour Ecto.Type

  @type t() :: String.t()

  @impl Ecto.Type
  def type, do: :string

  @impl Ecto.Type
  def load(data), do: cast(data)

  @impl Ecto.Type
  def cast(data) when is_binary(data) do
    {:ok, ":#{data}"}
  end

  def cast(_), do: :error

  def cast!(data) do
    case cast(data) do
      {:ok, data} -> data
      _ -> raise "can't cast:: #{inspect(data)} ::into #{inspect(__MODULE__)}"
    end
  end

  @impl Ecto.Type
  def dump(data) when is_binary(data), do: {:ok, data}
  def dump(_), do: :error

  @impl Ecto.Type
  def equal?(a, a), do: true
  def equal?(_, _), do: false

  @impl Ecto.Type
  def embed_as(_), do: :dump
end
