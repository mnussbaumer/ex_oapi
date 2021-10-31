defmodule ExOAPI.Helpers.Casting do
  @type valid_key :: String.t() | atom()
  @type key_tuple :: {valid_key(), valid_key()}
  @spec translate(
          final :: map() | {:ok, map()} | {:error, term()},
          from :: map() | list(map()),
          list(key_tuple)
        ) :: {:ok, map()} | {:error, :invalid_args} | {:error, {:missing_key, atom()}}
  @spec translate(
          final :: map() | {:ok, map()} | {:error, term()},
          from :: map(),
          list(key_tuple),
          Keyword.t()
        ) ::
          {:ok, map()} | {:error, :invalid_args} | {:error, {:missing_key, atom()}}
  def translate(from_map, original_to_final_keys)
      when is_map(from_map) and is_list(original_to_final_keys),
      do: translate(from_map, from_map, original_to_final_keys)

  def translate(from_map, original_to_final_keys, opts)
      when is_map(from_map) and is_list(original_to_final_keys) and is_list(opts),
      do: translate(from_map, from_map, original_to_final_keys, opts)

  def translate(acc_map, from_map, original_to_final_keys, opts \\ [])

  def translate(acc_map, from_list, original_to_final_keys, opts) when is_list(from_list) do
    Enum.reduce_while(from_list, [], fn original, acc ->
      case translate(acc_map, original, original_to_final_keys, opts) do
        {:ok, translated} -> {:cont, [translated | acc]}
        {:error, what} -> {:halt, {:error, {what, original}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      translated -> {:ok, Enum.reverse(translated)}
    end
  end

  def translate({:ok, acc_map}, from_map, original_to_final_keys, opts),
    do: translate(acc_map, from_map, original_to_final_keys, opts)

  def translate(acc_map, from_map, original_to_final_keys, opts)
      when is_map(acc_map) and is_map(from_map) do
    required? = Keyword.get(opts, :enforce_keys, false)

    original_to_final_keys
    |> Enum.reduce_while(acc_map, fn
      {original, final}, acc ->
        case Map.fetch(from_map, original) do
          {:ok, value} -> {:cont, Map.put(acc, final, value)}
          :error when required? -> {:halt, {:error, {:missing_key, original}}}
          _ -> {:cont, Map.put(acc, final, nil)}
        end

      {original, final, default}, acc ->
        case Map.fetch(from_map, original) do
          {:ok, value} -> {:cont, Map.put(acc, final, value)}
          :error when required? -> {:halt, {:error, {:missing_key, original}}}
          _ -> {:cont, Map.put(acc, final, default)}
        end
    end)
    |> case do
      {:error, _} = error -> error
      valid -> {:ok, valid}
    end
  end

  def translate(_, _, _, _), do: {:error, :invalid_args}
end
