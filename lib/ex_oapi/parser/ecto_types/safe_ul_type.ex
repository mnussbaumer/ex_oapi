defmodule ExOAPI.EctoTypes.SafeUL do
  @behaviour Ecto.Type

  @type t() :: String.t()

  @impl Ecto.Type
  def type, do: :string

  @impl Ecto.Type
  def load(data), do: cast(data)

  @impl Ecto.Type
  def cast(data) when is_binary(data) do
    with data <- String.downcase(data),
         {:ok, data} <- ExOAPI.EctoTypes.Underscore.cast(data) do
      {:ok, data}
    end
  end

  def cast(_), do: :error

  @impl Ecto.Type
  def dump(data) when is_binary(data), do: {:ok, data}
  def dump(_), do: :error

  @impl Ecto.Type
  def equal?(a, a), do: true
  def equal?(_, _), do: false

  @impl Ecto.Type
  def embed_as(_), do: :self
end
