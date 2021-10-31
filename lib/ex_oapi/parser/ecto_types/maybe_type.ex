defmodule ExOAPI.EctoTypes.Maybe do
  use Ecto.ParameterizedType

  def type(_params), do: :map

  def init(opts),
    do: Enum.into(opts, %{})

  def cast(nil, params),
    do: {:ok, Map.get(params, :default)}

  def cast(data, params) do
    Enum.reduce_while(params.types, :error, fn {_, validation}, _ ->
      case validation.(data, params) do
        {:ok, _} = ok -> {:halt, ok}
        _ -> {:cont, :error}
      end
    end)
  end

  def load(nil, _loader, params) do
    {:ok, Map.get(params, :default)}
  end

  def load(data, _loader, _params) do
    {:ok, data}
  end

  def dump(nil, _dumper, params) do
    {:ok, Map.get(params, :default)}
  end

  def dump(data, _dumper, _params) do
    {:ok, data}
  end

  def equal?(a, b, _params) do
    a == b
  end

  def embed_as?(_), do: :dump
end
