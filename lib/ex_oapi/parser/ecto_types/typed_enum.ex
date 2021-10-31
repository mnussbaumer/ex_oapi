defmodule ExOAPI.EctoTypes.TypedEnum do
  defmacro __before_compile__(_env) do
    # these are inserted in the before_compile hook to give opportunity to the
    # implementing module to define additional variations
    quote do
      def cast(_), do: :error
      def dump(_), do: :error
      defp get_term(data), do: data
    end
  end

  defmacro __using__(opts) do
    values = Keyword.fetch!(opts, :values)
    mod = __CALLER__.module

    quote bind_quoted: [atoms: values, mod: mod] do
      @before_compile ExOAPI.EctoTypes.TypedEnum

      strings = Enum.map(atoms, fn entry -> Atom.to_string(entry) end)
      mapped = Enum.zip(strings, atoms) |> Enum.into(%{})

      @behaviour Ecto.Type
      @impl Ecto.Type
      def type, do: :string

      strings = Enum.map(atoms, fn entry -> Atom.to_string(entry) end)
      mapped = Enum.zip(strings, atoms) |> Enum.into(%{})

      Module.put_attribute(mod, :valid_atoms, atoms)
      Module.put_attribute(mod, :valid_strings, strings)
      Module.put_attribute(mod, :validation_mappings, mapped)

      @type t() :: unquote(Enum.reduce(Enum.reverse(atoms), &{:|, [], [&1, &2]}))

      @spec values(:atoms | :strings) :: list(t()) | list(String.t())
      def values(type \\ :atoms)
      def values(:atoms), do: unquote(atoms)
      def values(:strings), do: unquote(strings)

      @impl Ecto.Type
      def load(data), do: cast(data)

      @impl Ecto.Type
      @doc false
      def cast(data) when is_atom(data) and data in unquote(atoms), do: {:ok, data}

      def cast(data) when is_binary(data) and data in unquote(strings),
        do: {:ok, String.to_atom(data)}

      @impl Ecto.Type
      @doc false
      def dump(data) when is_atom(data) and data in unquote(atoms),
        do: {:ok, Atom.to_string(data)}

      def dump(data) when is_binary(data) and data in unquote(strings),
        do: {:ok, data}

      @doc false
      def dump!(data) do
        case dump(data) do
          {:ok, value} ->
            value

          _ ->
            raise Ecto.CastError,
              message: "Unable to dump:: #{inspect(data)} ::into:: #{inspect(unquote(mod))}",
              type: unquote(mod),
              value: data
        end
      end

      @impl Ecto.Type
      @doc false
      def embed_as(_), do: :dump

      @impl Ecto.Type
      @doc false
      def equal?(term_1, term_1), do: true
      def equal?(term_1, term_2), do: get_term(term_1) == get_term(term_2)

      defp get_term(data) when is_atom(data) and data in unquote(atoms),
        do: data

      defp get_term(data) when is_binary(data) and data in unquote(strings),
        do: @validation_mappings[data]
    end
  end
end
